-- Parameter from Datadome SPOA 
DATADOME_REQUEST_HEADERS_PARAMETER          = "txn.dd.x_datadome_request_headers"
DATADOME_RESPONSE_HEADERS_PARAMETER         = "txn.dd.x_datadome_headers"
DATADOME_RESPONSE_CODE_PARAMETER            = "txn.dd.x_datadome_response"
DATADOME_RESPONSE_BODY_BLOCKED_PARAMETER    = "txn.dd.body"

-- Parameter for routing between nominal backend and failure backend in haproxy configuration
DATADOME_STATUS_VARIABLE = "txn.dd.status"

-- Prefix of variable set by Datadome SPOA 
VAR_PREFIX="txn.dd."

-- Separator for Headers 
HEADER_SEPARATOR = "@@"

-- Utils 
function split(s, delimiter)
    result = {};
    for match in (s..delimiter):gmatch("(.-)"..delimiter) do
        table.insert(result, match);
    end
    return result;
end

function is_blocked_content(txn)
	responseCode = txn:get_var(DATADOME_RESPONSE_CODE_PARAMETER)
    return (responseCode ~= nil and (responseCode == 401 or responseCode == 403 ))
end

function formatPattern(s)
    return (string.gsub(s, "-", "%%-"))
end

function trim(s)
    return (string.gsub(s, "^%s*(.-)%s*$", "%1"))
end

-- Fetch adaptation for Datadome variables

-- See https://docs.datadome.co for specification
core.register_fetches("TimeRequest",function(txn)
    return string.format("%i%06i",txn.f:date(),txn.f:date_us())
end)


core.register_fetches("APIConnectionState",function(txn)
    if (txn.f:http_first_req() == 0) then
        return "reuse"
    else
        return "new"
    end
end)

core.register_fetches("Protocol",function(txn)
    if (txn.f:ssl_fc() == 0) then
        return "http"
    else
        return "https"
    end
end)

core.register_converters("length",function(str)
    if (str ~= nil) then
        return string.len(str)
    else
        return nil
    end

end)

-- Add headers to the request to the backend (either nominal or failure backend)
core.register_action("Datadome_request_hook", { "http-req" }, function(txn)
    -- Add the headers given by API server to the backend request
    requestHeaders = txn:get_var(DATADOME_REQUEST_HEADERS_PARAMETER);
    if (requestHeaders ~= nil ) then
        for k,headerNameValue in pairs(split(requestHeaders,HEADER_SEPARATOR)) do
                sepPosition = string.find(headerNameValue,": ")
                if (sepPosition ~= nil) then
                    -- The ":" and " " will be added by req_set_header so we truncate both Header name and header value
                    txn.http:req_set_header(string.sub(headerNameValue,1,sepPosition-1),string.sub(headerNameValue,sepPosition+2));
                end
        end
    end
    -- Prepare the blocking backend
    if (is_blocked_content(txn)) then
        txn:set_var(DATADOME_STATUS_VARIABLE,"blocked")
    else
        txn:set_var(DATADOME_STATUS_VARIABLE,"ok")
    end
end)

-- Add headers to the response to the end-user customer
core.register_action("Datadome_response_hook", { "http-res" }, function(txn)
    responseHeaders = txn:get_var(DATADOME_RESPONSE_HEADERS_PARAMETER);
    if (responseHeaders ~= nil ) then
        for k,headerNameValue in pairs(split(responseHeaders,HEADER_SEPARATOR)) do
                sepPosition = string.find(headerNameValue,": ")
                if (sepPosition ~= nil) then
                    -- The ":" and " " will be added by req_add_header so we truncate both Header name and header value
                    txn.http:res_add_header(string.sub(headerNameValue,1,sepPosition-1),string.sub(headerNameValue,sepPosition+2));
                end
        end
    end
end)

-- Blocking page backend
core.register_service("failure_service", "http", function(applet)
      local response = applet:get_var(DATADOME_RESPONSE_BODY_BLOCKED_PARAMETER);
      local response_code = applet:get_var(DATADOME_RESPONSE_CODE_PARAMETER);
      applet:set_status(response_code)
      applet:add_header("content-length", string.len(response))
      applet:add_header("content-type", "text/html")
      applet:start_response()
      applet:send(response)
end)

-- Utils for Logs DataDome Headers
core.register_fetches("ddHeaders", function(txn, value)
    requestHeaders = txn:get_var(DATADOME_REQUEST_HEADERS_PARAMETER);

    if (requestHeaders ~= nil) then
        searchPattern = formatPattern(value) .. ": [%w_*%s]*"
        header = string.match(requestHeaders, searchPattern)
        if (header ~= nil) then
            searchPattern2 = " [%w_*%s]*"
            headerValue = string.match(header, searchPattern2)
            return trim(headerValue)
        end
    end 
end)
