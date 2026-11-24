using SHA

function normalize_anchor_tokens(rule_id::String, message::String)
    parts = filter(!isempty, split(strip(message)))
    return join(parts, " ")
end

function diagnostic_fingerprint(rule_id::String, path::String, anchor_line::Int, message::String, index::Int)
    payload = "v1:$(rule_id)|$(path)|$(anchor_line)|$(normalize_anchor_tokens(rule_id, message))|$(index)"
    return "v1:" * bytes2hex(sha1(payload))
end

function pattern_hash(snippet::String)
    return "v1:" * bytes2hex(sha1(snippet))
end
