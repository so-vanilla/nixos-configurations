M = {}

function M.concat(...)
    local result = {}
    for _, list in ipairs({...}) do
       for _, item in ipairs(list) do
          table.insert(result, item)
       end
    end
    return result
end

return M
