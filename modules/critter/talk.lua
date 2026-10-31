-- talk.lua — Simple UI
-- The conversation of the Critter module: the critter opens with a line and the
-- user picks one of a few answers, or asks for another phrase. Choosing an
-- answer moves the critter's mood (mood.lua) and hands its reply back to the
-- module, which shows it in the bubble. Some answers lead on to a second window:
-- a book suggestion, a game (games.lua) or a quote. The window that shows the exchange is
-- talk_window.lua.

local Dialog     = require("modules/critter/dialog")
local GameLines  = require("modules/critter/game_lines")
local Games      = require("modules/critter/games")
local Mood       = require("modules/critter/mood")
local TalkWindow = require("modules/critter/talk_window")
local _          = require("infra/sui_i18n").translate

local Talk = {}

-- Mood gain of opening a suggested book.
local OPEN_GAIN = 3

-- Mood gain of winning a round or answering a question right.
local WIN_GAIN = 1

-- The mood on today's date: a new day starts from that day's cap.
local function currentState()
    return Mood.rollDay(Mood.read(), os.date("%Y-%m-%d"))
end

local function applyDelta(delta)
    Mood.write(Mood.applyChoice(currentState(), delta))
end

local function currentTier()
    return Mood.tier(currentState().score)
end

-- Arguments the window takes from the conversation's opts, plus `extra`.
local function windowOpts(opts, extra)
    local window = {
        anchor       = opts.anchor,
        side         = opts.side,
        critter_rect = opts.critter_rect,
        style        = opts.style,
        unit         = opts.unit,
        scale        = opts.scale,
        faces        = opts.faces,
    }
    for k, v in pairs(extra) do window[k] = v end
    return window
end

-- Second step of a book suggestion: offers an unopened book of the library, or
-- answers with the reply of `option` when there is none. `skip` is the book that
-- was offered before.
local function suggest(opts, option, skip)
    local book = opts.library.next(skip and skip.fp)
    if not book then
        opts.on_reply(option.reply(currentTier()))
        return
    end
    local lines = Dialog.suggestion(book, opts.facts, currentTier())
    TalkWindow.open(windowOpts(opts, {
        opener  = lines.opener,
        options = {
            { text = lines.open_text, on_pick = function()
                if opts.library.open(book.fp) then
                    applyDelta(OPEN_GAIN)
                else
                    suggest(opts, option, book)
                end
            end },
            { text = lines.later_text, on_pick = function()
                opts.on_reply(lines.later_reply)
            end },
        },
        other = { text = lines.another_text, on_pick = function() suggest(opts, option, book) end },
    }))
end

-- Quotes the critter reads and asks about: the built-in ones and the user's own,
-- gathered once for the conversation.
local function quotes(opts)
    if not opts.quote_pool then
        local pool = {}
        for _i, entry in ipairs(require("modules/quotes")) do pool[#pool + 1] = entry end
        for _i, entry in ipairs(require("modules/module_quote").customQuotes()) do pool[#pool + 1] = entry end
        opts.quote_pool = pool
    end
    return opts.quote_pool
end

-- Window of the last step of a game round: the user plays `again_text` or stops.
local function roundResult(opts, text, again_text, again)
    TalkWindow.open(windowOpts(opts, {
        opener  = text,
        options = {
            { text = again_text, on_pick = again },
            { text = GameLines.enough(), on_pick = function()
                opts.on_reply(GameLines.done(currentTier()))
            end },
        },
    }))
end

-- One round of rock, paper, scissors.
local function rpsRound(opts)
    local options = {}
    for _i, move in ipairs(Games.MOVES) do
        options[#options + 1] = {
            text    = GameLines.name(move),
            on_pick = function()
                local mine, outcome = Games.rps(move, math.random)
                if outcome == "win" then applyDelta(WIN_GAIN) end
                roundResult(opts, GameLines.rpsResult(mine, outcome, currentTier()),
                    GameLines.again(), function() rpsRound(opts) end)
            end,
        }
    end
    TalkWindow.open(windowOpts(opts, { opener = GameLines.rpsPrompt(), options = options }))
end

-- One toss of the coin.
local function coinRound(opts)
    local options = {}
    for _i, call in ipairs({ "heads", "tails" }) do
        options[#options + 1] = {
            text    = GameLines.name(call),
            on_pick = function()
                local side, right = Games.coin(call, math.random)
                if right then applyDelta(WIN_GAIN) end
                roundResult(opts, GameLines.coinResult(side, right, currentTier()),
                    GameLines.again(), function() coinRound(opts) end)
            end,
        }
    end
    TalkWindow.open(windowOpts(opts, { opener = GameLines.coinPrompt(), options = options }))
end

-- One "who said it?" question.
local function quizRound(opts)
    local quiz = Games.quiz(quotes(opts), math.random)
    if not quiz then
        opts.on_reply(GameLines.done(currentTier()))
        return
    end
    local options = {}
    for i, author in ipairs(quiz.choices) do
        options[#options + 1] = {
            text    = author,
            on_pick = function()
                local right = i == quiz.answer
                if right then applyDelta(WIN_GAIN) end
                roundResult(opts, GameLines.quizResult(right, quiz.author, currentTier()),
                    GameLines.anotherOne(), function() quizRound(opts) end)
            end,
        }
    end
    TalkWindow.open(windowOpts(opts, {
        opener       = GameLines.quizPrompt(quiz.quote),
        opener_lines = Games.QUOTE_LINES,
        options      = options,
    }))
end

-- The choice of games.
local function playMenu(opts)
    local function game(text, round)
        return { text = text, on_pick = function() round(opts) end }
    end
    TalkWindow.open(windowOpts(opts, {
        opener  = GameLines.menuPrompt(),
        options = {
            game(GameLines.rpsText(),  rpsRound),
            game(GameLines.coinText(), coinRound),
            game(GameLines.quizText(), quizRound),
        },
    }))
end

-- Reads a quote; the critter comments on it when the user is done. `skip` is the
-- position of the quote read before.
local function readQuote(opts, skip)
    local entry, index = Games.pickQuote(quotes(opts), math.random, skip)
    TalkWindow.open(windowOpts(opts, {
        opener       = GameLines.quoteText(entry),
        opener_lines = Games.QUOTE_LINES,
        options      = {
            { text = GameLines.anotherOne(), on_pick = function() readQuote(opts, index) end },
            { text = GameLines.thanks(), on_pick = function()
                opts.on_reply(GameLines.comment(currentTier(), math.random))
            end },
        },
    }))
end

--- Opens the conversation and returns its window.
--   opts.facts         facts about the moment (see phrases.lua)
--   opts.on_reply      function(reply): the critter answered; reply = { text, sub, mood }
--   opts.on_other      function(): the user asked for another phrase
--   opts.anchor        Geom of the module's bubble, which the conversation takes over
--   opts.side          "left" | "right": where the critter stands, nil without one
--   opts.critter_rect  Geom of the critter
--   opts.style         "pixel" | "smooth": style of the bubble
--   opts.unit          pixel size of the pixel-art drawing, in px
--   opts.scale         size factor of the module
--   opts.faces         { message, message_bold, answer }: the faces of the
--                      module's text, which the conversation follows
--   opts.on_accept     function(offer): the user accepted the challenge on offer
--                      (opts.facts.challenge.offer)
--   opts.library       { next = function(skip_fp) -> { fp, title, authors } | nil,
--                        open = function(fp) -> boolean }: where a book suggestion
--                      finds an unopened book and opens it (false: the file is
--                      gone); without it the suggestion answers like any option
function Talk.open(opts)
    local exchange = Dialog.pick(opts.facts, Mood.tier(Mood.read().score))

    local options = {}
    for _i, option in ipairs(exchange and exchange.options or {}) do
        options[#options + 1] = {
            text    = option.text,
            on_pick = function()
                applyDelta(option.delta)
                local challenge = opts.facts and opts.facts.challenge
                if option.accept and opts.on_accept and challenge and challenge.offer then
                    opts.on_accept(challenge.offer)
                end
                if option.play then
                    playMenu(opts)
                elseif option.quote then
                    readQuote(opts, nil)
                elseif option.recommend and opts.library then
                    suggest(opts, option, nil)
                else
                    opts.on_reply(option.reply(currentTier()))
                end
            end,
        }
    end

    return TalkWindow.open(windowOpts(opts, {
        opener  = exchange and exchange.opener or nil,
        options = options,
        other   = { text = _("Say something else…"), on_pick = opts.on_other },
    }))
end

return Talk
