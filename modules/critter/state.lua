-- state.lua — Simple UI
-- Shallow copy and comparison of the plain state tables kept by mood.lua,
-- reactions.lua and challenge.lua.

local State = {}

--- A copy of `state` with `changes` applied.
function State.copy(state, changes)
    local new = {}
    for k, v in pairs(state) do new[k] = v end
    for k, v in pairs(changes) do new[k] = v end
    return new
end

--- Whether `a` and `b` hold the same values, ignoring the fields in `skip`.
function State.same(a, b, skip)
    for k, v in pairs(a) do
        if not (skip and skip[k]) and b[k] ~= v then return false end
    end
    for k in pairs(b) do
        if not (skip and skip[k]) and a[k] == nil then return false end
    end
    return true
end

return State
