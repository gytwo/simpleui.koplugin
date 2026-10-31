-- games.lua — Simple UI
-- Rules of the small games the Critter plays in the conversation: rock, paper,
-- scissors, heads or tails and "who said it?", and the pick of the quotes it
-- reads. Everything here is pure: `rand(n)` gives an integer from 1 to n
-- (math.random) and the quotes are { q, a, b? } entries (modules/quotes.lua).

local Games = {}

Games.MOVES = { "rock", "paper", "scissors" }

-- Longest quote that is read or asked about, in characters of what is shown (the
-- quote, its author and the words around them): the window holds five lines.
Games.MAX_QUOTE_LEN = 100
Games.QUOTE_LINES   = 5

-- Characters the quote and author are framed with: the marks, the dash and "Who said".
local QUOTE_FRAME_LEN = 12

-- Length of `text` in UTF-8 characters.
local function charCount(text)
    return select(2, text:gsub("[^\128-\191]", ""))
end

-- What each move beats.
local BEATS = { rock = "scissors", paper = "rock", scissors = "paper" }

--- The critter's move against `move`, and how it went for the user: "win",
--- "lose" or "draw".
function Games.rps(move, rand)
    local mine = Games.MOVES[rand(#Games.MOVES)]
    if mine == move then return mine, "draw" end
    return mine, BEATS[move] == mine and "win" or "lose"
end

--- The side the coin lands on ("heads" | "tails") and whether it is the `call`.
function Games.coin(call, rand)
    local side = rand(2) == 1 and "heads" or "tails"
    return side, side == call
end

-- Positions of the quotes short enough to be read; every quote when none is.
local function readable(quotes)
    local list = {}
    for i, entry in ipairs(quotes) do
        local shown = charCount(entry.q) + (entry.a and charCount(entry.a) or 0) + QUOTE_FRAME_LEN
        if shown <= Games.MAX_QUOTE_LEN then list[#list + 1] = i end
    end
    if #list == 0 then
        for i = 1, #quotes do list[i] = i end
    end
    return list
end

--- A quote to read, and its position in `quotes`. The one at position `skip`
--- is passed over unless it is the only choice.
function Games.pickQuote(quotes, rand, skip)
    local list = readable(quotes)
    if #list > 1 then
        for at, index in ipairs(list) do
            if index == skip then table.remove(list, at); break end
        end
    end
    local index = list[rand(#list)]
    return quotes[index], index
end

-- Moves the entries of `list` around, in place.
local function shuffle(list, rand)
    for i = #list, 2, -1 do
        local j = rand(i)
        list[i], list[j] = list[j], list[i]
    end
    return list
end

--- A "who said it?" question about a quote that has an author: { quote, author,
--- choices, answer }, where `choices` are three authors and `answer` the
--- position of the right one. nil when `quotes` has fewer than three authors.
function Games.quiz(quotes, rand)
    local signed = {}
    for _i, entry in ipairs(quotes) do
        if entry.a then signed[#signed + 1] = entry end
    end
    if #signed == 0 then return nil end

    local entry = Games.pickQuote(signed, rand)
    local others, seen = {}, { [entry.a] = true }
    for _i, other in ipairs(signed) do
        if not seen[other.a] then
            seen[other.a] = true
            others[#others + 1] = other.a
        end
    end
    if #others < 2 then return nil end

    shuffle(others, rand)
    local choices = shuffle({ entry.a, others[1], others[2] }, rand)
    local answer
    for i, author in ipairs(choices) do
        if author == entry.a then answer = i end
    end
    return { quote = entry.q, author = entry.a, choices = choices, answer = answer }
end

return Games
