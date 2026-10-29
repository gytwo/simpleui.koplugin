-- game_lines.lua — Simple UI
-- What the Critter says while it plays (games.lua) and when it reads a quote
-- (talk.lua). A set of lines holds `base` and, where the attitude changes, the
-- mood tiers of dialog.lua that override it; every line is a function so it is
-- translated when it is shown. Same voice and length rules as dialog.lua.

local _ = require("infra/sui_i18n").translate

local GameLines = {}

-- Mood of the critter's closing line for each tier; the other tiers play.
local TIER_MOOD = { grumpy = "grumpy", happy = "cheer", radiant = "love" }

-- The line of `set` for `tier`.
local function line(set, tier)
    return (set[tier] or set.base)()
end

-- Outcome lines of a round, as { win | lose | draw, or right | wrong = set }.
local RPS = {
    win = {
        base    = function() return _("You win. This time.") end,
        grumpy  = function() return _("You win. Hmph.") end,
        radiant = function() return _("You win! You're too good.") end,
    },
    lose = {
        base    = function() return _("I win.") end,
        grumpy  = function() return _("I win. Obviously.") end,
        radiant = function() return _("I win! Want to try again?") end,
    },
    draw = {
        base    = function() return _("A draw.") end,
        grumpy  = function() return _("A draw. Boring.") end,
        radiant = function() return _("A draw! We think alike.") end,
    },
}

local COIN = {
    right = {
        base    = function() return _("You called it.") end,
        grumpy  = function() return _("Lucky guess.") end,
        radiant = function() return _("You called it! Of course you did.") end,
    },
    wrong = {
        base    = function() return _("Not this time.") end,
        grumpy  = function() return _("Wrong. Next.") end,
        radiant = function() return _("Not this time. Again?") end,
    },
}

local QUIZ = {
    right = {
        base    = function() return _("Correct!") end,
        grumpy  = function() return _("Correct. Don't let it go to your head.") end,
        radiant = function() return _("Correct! You know your books.") end,
    },
    wrong = {
        base    = function(author) return string.format(_("It was %s."), author) end,
        grumpy  = function(author) return string.format(_("Wrong. It was %s."), author) end,
        radiant = function(author) return string.format(_("Close! It was %s."), author) end,
    },
}

local DONE = {
    base    = function() return _("Good game. Same time tomorrow?") end,
    grumpy  = function() return _("Fine. That's enough for me too.") end,
    radiant = function() return _("I love playing with you.") end,
}

-- Comments on a quote the critter has read; one is dealt at random.
local COMMENTS = {
    base = {
        function() return _("I'll keep that one on the shelf.") end,
        function() return _("Someone wrote that on purpose.") end,
        function() return _("I'll think about that all night.") end,
        function() return _("Short. Good. My kind of sentence.") end,
    },
    grumpy = {
        function() return _("Hm. I've read worse.") end,
        function() return _("Fine. That one can stay.") end,
    },
    happy = {
        function() return _("Oh, I like that one.") end,
        function() return _("That one made my day a little bigger.") end,
    },
    radiant = {
        function() return _("That's beautiful. Read it again?") end,
        function() return _("I want to frame that one.") end,
    },
}

function GameLines.menuPrompt() return _("What shall we play?") end
function GameLines.rpsText()    return _("Rock, paper, scissors") end
function GameLines.coinText()   return _("Heads or tails") end
function GameLines.quizText()   return _("Guess the author") end

function GameLines.rpsPrompt()  return _("Rock, paper, scissors. Go.") end
function GameLines.coinPrompt() return _("I'm flipping. Call it.") end

function GameLines.quizPrompt(quote)
    return string.format(_("Who said “%s”?"), quote)
end

local NAMES = {
    rock     = function() return _("Rock") end,
    paper    = function() return _("Paper") end,
    scissors = function() return _("Scissors") end,
    heads    = function() return _("Heads") end,
    tails    = function() return _("Tails") end,
}

--- Name of a move (rock, paper, scissors) or a side of the coin (heads, tails).
function GameLines.name(id) return NAMES[id]() end

--- What the critter says after a round of rock, paper, scissors: its move and
--- the outcome ("win" | "lose" | "draw", for the user).
function GameLines.rpsResult(move, outcome, tier)
    return string.format("%s! %s", GameLines.name(move), line(RPS[outcome], tier))
end

--- After a toss: the side it landed on and whether the user called it.
function GameLines.coinResult(side, right, tier)
    return string.format("%s! %s", GameLines.name(side), line(COIN[right and "right" or "wrong"], tier))
end

--- After a "who said it?" question.
function GameLines.quizResult(right, author, tier)
    local set = QUIZ[right and "right" or "wrong"]
    return (set[tier] or set.base)(author)
end

function GameLines.again()      return _("Another round") end
function GameLines.anotherOne() return _("Another one") end
function GameLines.enough()     return _("Enough for now") end

--- The reply that ends a game, { mood, text }.
function GameLines.done(tier)
    return { mood = TIER_MOOD[tier] or "playful", text = line(DONE, tier) }
end

--- A quote as the critter reads it, with its author when it has one.
function GameLines.quoteText(entry)
    if not entry.a then return string.format("“%s”", entry.q) end
    return string.format("“%s” — %s", entry.q, entry.a)
end

function GameLines.thanks() return _("Thanks") end

--- The critter's comment on a quote, { mood, text }.
function GameLines.comment(tier, rand)
    local set = COMMENTS[tier] or COMMENTS.base
    return { mood = TIER_MOOD[tier] or "curious", text = set[rand(#set)]() }
end

return GameLines
