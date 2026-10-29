-- voice_lines.lua — Simple UI
-- Lines each bundled critter says in its own voice for the reactions of
-- reaction_lines.lua; they are dealt along with the general lines.
-- A line is { critter, kind, group, id, mood, text(data), sub?(data) }.

local _ = require("infra/sui_i18n").translate

local Voices = {}

-- Reaction of a situation and the groups of that reaction it fits.
local BOOK          = { name = "book",      kind = "book_finished",  groups = { "titled" } }
local SESSION       = { name = "session",   kind = "session",        groups = { "long" } }
local SESSION_SHORT = { name = "session",   kind = "session",        groups = { "short", "medium" } }
local COMEBACK      = { name = "comeback",  kind = "comeback",       groups = { "week" } }
local COMEBACK_ANY  = { name = "comeback",  kind = "comeback",       groups = { "few", "week", "month" } }
local BATTERY       = { name = "battery",   kind = "battery_low",    groups = { "low" } }
local CHARGING      = { name = "charging",  kind = "charging",       groups = { "charging" } }
local CHALLENGE     = { name = "challenge", kind = "challenge_done", groups = { "done" } }

-- The `n`th line of `critter` for `situation`, once per group it fits.
local function add(critter, situation, n, mood, text, sub)
    for _i, group in ipairs(situation.groups) do
        Voices[#Voices + 1] = {
            critter = critter, kind = situation.kind, group = group,
            id = string.format("v_%s_%s_%d_%s", critter, situation.name, n, group),
            mood = mood, text = text, sub = sub,
        }
    end
end

-- Suey.

add("suey", BOOK, 1, "happy",
    function(d) return string.format(_("%s, finished? Acceptable."), d.title) end,
    function() return _("I'll allow a purr.") end)
add("suey", SESSION, 1, "sleepy",
    function() return _("Long session. I napped twice.") end,
    function() return _("On your book, mostly.") end)
add("suey", COMEBACK_ANY, 1, "shy",
    function() return _("Oh. You're back.") end,
    function() return _("I wasn't waiting. Much.") end)
add("suey", BATTERY, 1, "surprised",
    function() return _("Low battery. Do something.") end,
    function() return _("Or I'll knock it off the shelf.") end)
add("suey", CHARGING, 1, "sleepy",
    function() return _("Warm cable. Mine now.") end,
    function() return _("Do not disturb.") end)
add("suey", CHALLENGE, 1, "love",
    function() return _("Challenge done. Good human.") end,
    function() return _("Chin scratch accepted.") end)

-- Chonk.

add("chonk", BOOK, 1, "surprised",
    function(d) return string.format(_("%s is over. Mongo is appalled."), d.title) end,
    function() return _("He wanted a sequel.") end)
add("chonk", SESSION, 1, "cheer",
    function() return _("That's a lot of reading. Iconic.") end,
    function() return _("I looked fabulous watching.") end)
add("chonk", COMEBACK, 1, "playful",
    function() return _("A week! Do you know what I did?") end,
    function() return _("Nothing. Beautifully.") end)
add("chonk", BATTERY, 1, "surprised",
    function() return _("Low battery?! Unacceptable!") end,
    function() return _("You know how I feel about that.") end)
add("chonk", CHARGING, 1, "happy",
    function() return _("Ooh, a warm cable. I deserve this.") end,
    function() return _("Thank you. Obviously.") end)
add("chonk", CHALLENGE, 1, "party",
    function() return _("Challenge met! Obviously I helped.") end,
    function() return _("I supervised. Very hard.") end)

-- Tulu.

add("tulu", BOOK, 1, "party",
    function(d) return string.format(_("%s, finished. The deep approves."), d.title) end,
    function() return _("I felt a ripple of joy.") end)
add("tulu", SESSION, 1, "happy",
    function() return _("A deep dive. I felt at home.") end,
    function() return _("Come up for air.") end)
add("tulu", COMEBACK_ANY, 1, "shy",
    function() return _("The tides brought you back.") end,
    function() return _("I counted every wave.") end)
add("tulu", BATTERY, 1, "surprised",
    function() return _("Low battery. The abyss calls.") end,
    function() return _("Charger. Now. Please.") end)
add("tulu", CHARGING, 1, "sleepy",
    function() return _("Warm currents. Lovely.") end,
    function() return _("Wake me at high tide.") end)
add("tulu", CHALLENGE, 1, "cheer",
    function() return _("Challenge met. The deep rejoices.") end,
    function() return _("Tentacles crossed. And clapping.") end)

-- Frankie.

add("frankie", BOOK, 1, "party",
    function(d) return string.format(_("%s finished. I'm all stitches!"), d.title) end,
    function() return _("Proud in every patch.") end)
add("frankie", SESSION, 1, "surprised",
    function() return _("Long read. I'm coming apart!") end,
    function() return _("Just a seam. Nothing serious.") end)
add("frankie", COMEBACK_ANY, 1, "shy",
    function() return _("You're back! I nearly unravelled.") end,
    function() return _("Missed you. Every patch.") end)
add("frankie", BATTERY, 1, "surprised",
    function() return _("Low battery. My seams tingle.") end,
    function() return _("Please, a charger.") end)
add("frankie", CHARGING, 1, "playful",
    function() return _("Zzzap. That tickles.") end,
    function() return _("Good tickle. Keep going.") end)
add("frankie", CHALLENGE, 1, "cheer",
    function() return _("Challenge met! Bursting at the seams!") end,
    function() return _("In a good way.") end)

-- Vlad.

add("vlad", BOOK, 1, "happy",
    function(d) return string.format(_("%s is done. Splendid."), d.title) end,
    function() return _("Worthy of the long night.") end)
add("vlad", SESSION, 1, "love",
    function() return _("A long night's reading. Delightful.") end,
    function() return _("The dawn found us both.") end)
add("vlad", COMEBACK_ANY, 1, "sad",
    function() return _("Days without you. Dreadful.") end,
    function() return _("I stared at the moon. Alone.") end)
add("vlad", BATTERY, 1, "surprised",
    function() return _("Low battery. I fade, I fade…") end,
    function() return _("Dramatically. But truly.") end)
add("vlad", CHARGING, 1, "happy",
    function() return _("Power flows. I feel alive.") end,
    function() return _("Almost.") end)
add("vlad", CHALLENGE, 1, "cheer",
    function() return _("Challenge met. Magnificent.") end,
    function() return _("I'll flash a fang for you.") end)

-- Sholmes.

add("sholmes", BOOK, 1, "cheer",
    function(d) return string.format(_("%s: case closed."), d.title) end,
    function() return _("The butler did it. Always.") end)
add("sholmes", SESSION, 1, "curious",
    function() return _("A long session. Elementary.") end,
    function() return _("You read like a detective.") end)
add("sholmes", COMEBACK, 1, "curious",
    function() return _("A week away. I deduced it.") end,
    function() return _("Dust on the shelf was a clue.") end)
add("sholmes", BATTERY, 1, "surprised",
    function() return _("Battery low. Elementary.") end,
    function() return _("Find the charger. Quickly.") end)
add("sholmes", CHARGING, 1, "happy",
    function() return _("Charging. As I deduced.") end,
    function() return _("The cable never lies.") end)
add("sholmes", CHALLENGE, 1, "cheer",
    function() return _("Challenge met. As predicted.") end,
    function() return _("Evidence is clear. Well done.") end)

-- Argos.

add("argos", BOOK, 1, "party",
    function(d) return string.format(_("%s! You finished it! Good!"), d.title) end,
    function() return _("I'm wagging so hard!") end)
add("argos", SESSION, 1, "love",
    function() return _("You read all that? Amazing!") end,
    function() return _("I waited. Good dog.") end)
add("argos", COMEBACK, 1, "cheer",
    function() return _("YOU'RE BACK!") end,
    function() return _("I watched the door all week.") end)
add("argos", BATTERY, 1, "surprised",
    function() return _("Low battery! Should I fetch it?") end,
    function() return _("Fetch is my favourite.") end)
add("argos", CHARGING, 1, "happy",
    function() return _("Charging! Good, good device!") end,
    function() return _("I'd give it a pat.") end)
add("argos", CHALLENGE, 1, "party",
    function() return _("Challenge met! Best day ever!") end,
    function() return _("Can we do it again?") end)

-- Hazel.

add("hazel", BOOK, 1, "cheer",
    function(d) return string.format(_("%s, finished. Pure magic."), d.title) end,
    function() return _("The cauldron is bubbling.") end)
add("hazel", SESSION, 1, "love",
    function() return _("Hours gone like a spell.") end,
    function() return _("Time bends around good books.") end)
add("hazel", COMEBACK, 1, "surprised",
    function() return _("You vanished for a week!") end,
    function() return _("I nearly cast a search spell.") end)
add("hazel", BATTERY, 1, "surprised",
    function() return _("Low battery. My wand's flickering.") end,
    function() return _("Quick, a recharge charm!") end)
add("hazel", CHARGING, 1, "happy",
    function() return _("Charging. A tiny spell.") end,
    function() return _("Cosy, crackling, wonderful.") end)
add("hazel", CHALLENGE, 1, "cheer",
    function() return _("Challenge met! Hocus-pocus!") end,
    function() return _("I'll stir in a little luck.") end)

-- Short and medium sessions.

add("suey", SESSION_SHORT, 1, "happy",
    function() return _("A little reading. Good enough.") end,
    function() return _("I'll allow a short nap.") end)
add("chonk", SESSION_SHORT, 1, "playful",
    function() return _("A quick read. I approve.") end,
    function() return _("Obviously I do.") end)
add("tulu", SESSION_SHORT, 1, "happy",
    function() return _("A small dip in the pages.") end,
    function() return _("The deep is patient.") end)
add("frankie", SESSION_SHORT, 1, "cheer",
    function() return _("A few pages, neatly stitched.") end,
    function() return _("Not one seam showing.") end)
add("vlad", SESSION_SHORT, 1, "happy",
    function() return _("A brief read. Elegant.") end,
    function() return _("Not all nights need be long.") end)
add("sholmes", SESSION_SHORT, 1, "curious",
    function() return _("A short session. Noted.") end,
    function() return _("I observe everything.") end)
add("argos", SESSION_SHORT, 1, "cheer",
    function() return _("You read! I'm so happy!") end,
    function() return _("Even a little is good!") end)
add("hazel", SESSION_SHORT, 1, "happy",
    function() return _("A quick spell of reading.") end,
    function() return _("Small magic counts too.") end)

-- Returns after three days or more.

add("chonk", COMEBACK_ANY, 2, "playful",
    function() return _("Oh, NOW you remember me.") end,
    function() return _("I was busy. Being fabulous.") end)
add("sholmes", COMEBACK_ANY, 2, "curious",
    function() return _("You were away. I noticed.") end,
    function() return _("The dust told me.") end)
add("argos", COMEBACK_ANY, 2, "cheer",
    function() return _("YOU'RE BACK!") end,
    function() return _("I missed you so much!") end)
add("hazel", COMEBACK_ANY, 2, "surprised",
    function() return _("You're back! I was worried.") end,
    function() return _("I nearly cast a search spell.") end)

return Voices
