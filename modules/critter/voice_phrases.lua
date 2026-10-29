-- voice_phrases.lua — Simple UI
-- Phrases each bundled critter says in its own voice besides the general ones
-- of phrases.lua, in the same categories and with the same fields.
-- A phrase is { id, critter, cat, mood, when(f), text(f), sub?(f) }.
-- Each critter lists its variants per situation; a situation with several
-- variants gives the critter a deck to rotate through.
--
-- Voices: Suey an aloof cat; Chonk a vain, dramatic show cat and former Grand
-- Champion, with a pet dinosaur, Mongo; Tulu a small, polite elder horror;
-- Frankie a cheerful stitched-together creature; Vlad a theatrical vampire;
-- Sholmes a detective who deduces everything; Argos a devoted dog; Hazel a
-- warm, slightly chaotic witch. Same length rules as dialog.lua.

local _  = require("infra/sui_i18n").translate
local N_ = require("infra/sui_i18n").ngettext

local Voices = {}

local function atLeast(value, n) return value ~= nil and value >= n end

-- Situations: the category of their phrases and when they apply, from the
-- facts of phrases.lua.
local SITUATIONS = {
    greet_morning   = { cat = "greeting", when = function(f) return f.period == "morning" end },
    greet_afternoon = { cat = "greeting", when = function(f) return f.period == "afternoon" end },
    greet_evening   = { cat = "greeting", when = function(f) return f.period == "evening" end },
    greet_night     = { cat = "greeting", when = function(f) return f.period == "night" end },
    streak          = { cat = "streak",   when = function(f) return atLeast(f.streak, 2) end },
    streak_paused   = { cat = "streak",   when = function(f) return f.streak == 0 end },
    today           = { cat = "today",    when = function(f) return atLeast(f.today_secs, 60) end },
    books_year      = { cat = "books",    when = function(f) return atLeast(f.books_year, 1) end },
    book_progress   = { cat = "reading",
                        when = function(f) return f.book ~= nil and f.book.days < 3 and f.book.percent < 90 end },
    book_waiting    = { cat = "reading",  when = function(f) return f.book ~= nil and f.book.days >= 3 end },
    goal_day        = { cat = "special",
                        when = function(f) return f.daily_goal_secs > 0 and atLeast(f.today_secs, f.daily_goal_secs) end },
    monday          = { cat = "calendar", when = function(f) return f.weekday == 2 end },
    weekend         = { cat = "calendar", when = function(f) return f.weekday == 1 or f.weekday == 7 end },
    anytime         = { cat = "generic",  when = function() return true end },
}

-- Situations in a fixed order, so the phrases are listed the same way every run.
local ORDER = {
    "greet_morning", "greet_afternoon", "greet_evening", "greet_night", "streak", "streak_paused",
    "today", "books_year", "book_progress", "book_waiting", "goal_day", "monday", "weekend", "anytime",
}

-- Adds the variants { mood, text, sub? } of `critter`, listed by situation.
local function voice(critter, situations)
    for _i, name in ipairs(ORDER) do
        local situation = SITUATIONS[name]
        for n, variant in ipairs(situations[name] or {}) do
            Voices[#Voices + 1] = {
                id = string.format("v_%s_%s_%d", critter, name, n), critter = critter,
                cat = situation.cat, mood = variant.mood, when = situation.when,
                text = variant.text, sub = variant.sub,
            }
        end
    end
end

-- Whole minutes read today.
local function minutes(f) return math.floor(f.today_secs / 60) end

-- Suey.

voice("suey", {
    greet_morning = {
        { mood = "happy", text = function() return _("Morning. The sunbeam is mine.") end,
          sub = function() return _("You may read beside it.") end },
        { mood = "neutral", text = function() return _("Morning. I slept on your book.") end,
          sub = function() return _("It's warm now. You're welcome.") end },
    },
    greet_afternoon = {
        { mood = "playful", text = function() return _("Afternoon. Nap or read?") end,
          sub = function() return _("Why not both.") end },
        { mood = "grumpy", text = function() return _("I've ignored you since noon.") end,
          sub = function() return _("Read, and I'll keep it up.") end },
    },
    greet_evening = {
        { mood = "love", text = function() return _("Evening. Lap time.") end,
          sub = function() return _("Bring the book.") end },
        { mood = "playful", text = function() return _("Evening. I knocked your pen off.") end,
          sub = function() return _("Now there's only the book.") end },
    },
    greet_night = {
        { mood = "curious", text = function() return _("Night. I patrol the shelf.") end,
          sub = function() return _("Read quietly.") end },
        { mood = "playful", text = function() return _("Night. I start sprinting at three.") end,
          sub = function() return _("Read before I do.") end },
    },
    streak = {
        { mood = "happy", text = function() return _("Streak intact. I'm impressed.") end,
          sub = function() return _("Don't tell anyone.") end },
        { mood = "neutral",
          text = function(f)
              return string.format(N_("%d day. I'd have quit on day one.",
                  "%d days. I'd have quit on day one.", f.streak), f.streak)
          end,
          sub = function() return _("Cats don't do routines.") end },
    },
    streak_paused = {
        { mood = "shy", text = function() return _("Your streak broke. Not me.") end,
          sub = function() return _("This time.") end },
    },
    today = {
        { mood = "playful", text = function() return _("Good reading today.") end,
          sub = function() return _("I supervised from the sill.") end },
        { mood = "neutral",
          text = function(f)
              local m = minutes(f)
              return string.format(N_("%d minute read. I judged it.", "%d minutes read. I judged each one.", m), m)
          end,
          sub = function() return _("Kindly. Don't get used to it.") end },
    },
    books_year = {
        { mood = "neutral",
          text = function(f)
              return string.format(N_("%d book this year. I read none.",
                  "%d books this year. I read none.", f.books_year), f.books_year)
          end,
          sub = function() return _("I sat on every one, though.") end },
    },
    book_progress = {
        { mood = "curious", text = function(f) return string.format(_("%s? I've read the cover."), f.book.title) end,
          sub = function() return _("Mostly with my face.") end },
    },
    book_waiting = {
        { mood = "sleepy", text = function(f) return string.format(_("%s is untouched. Good."), f.book.title) end,
          sub = function() return _("I've been sleeping on it.") end },
    },
    goal_day = {
        { mood = "happy", text = function() return _("Daily goal done. Now pet me.") end,
          sub = function() return _("That was my goal.") end },
    },
    monday = {
        { mood = "neutral", text = function() return _("Monday. Irrelevant to cats.") end,
          sub = function() return _("Every day is Saturday here.") end },
    },
    weekend = {
        { mood = "love", text = function() return _("Weekend. Two whole days of lap.") end,
          sub = function() return _("Plan accordingly.") end },
    },
    anytime = {
        { mood = "curious", text = function() return _("I've been staring at you for an hour.") end,
          sub = function() return _("It's a compliment. Probably.") end },
        { mood = "playful", text = function() return _("I pushed your bookmark off the shelf.") end,
          sub = function() return _("Your place is a mystery now.") end },
    },
})

-- Chonk.

voice("chonk", {
    greet_morning = {
        { mood = "cheer", text = function() return _("Good morning. I look incredible.") end,
          sub = function() return _("As always.") end },
        { mood = "happy", text = function() return _("Morning! I've already been adored.") end,
          sub = function() return _("By the mirror, but still.") end },
    },
    greet_afternoon = {
        { mood = "playful", text = function() return _("Afternoon. Read something worthy.") end,
          sub = function() return _("I'm watching.") end },
        { mood = "curious", text = function() return _("Afternoon. My fans want an update.") end,
          sub = function() return _("Read something. I'll post it.") end },
    },
    greet_evening = {
        { mood = "happy", text = function() return _("Evening. Time to be fabulous.") end,
          sub = function() return _("With a book, obviously.") end },
        { mood = "love", text = function() return _("Evening. Dim the lamp. I glow.") end,
          sub = function() return _("You can read by me.") end },
    },
    greet_night = {
        { mood = "sleepy", text = function() return _("Night. Beauty sleep soon.") end,
          sub = function() return _("Finish your chapter first.") end },
        { mood = "shy", text = function() return _("Night. Mongo is guarding the shelf.") end,
          sub = function() return _("He ate a bookmark. Ignore it.") end },
    },
    streak = {
        { mood = "cheer", text = function() return _("A streak! Naturally.") end,
          sub = function() return _("I inspired it.") end },
        { mood = "party",
          text = function(f)
              return string.format(N_("%d day! Champion behaviour.", "%d days! Champion behaviour.", f.streak), f.streak)
          end,
          sub = function() return _("I'd know. I'm a Grand Champion.") end },
    },
    streak_paused = {
        { mood = "surprised", text = function() return _("Your streak broke?! How does that LOOK?") end,
          sub = function() return _("People talk, you know.") end },
    },
    today = {
        { mood = "playful", text = function() return _("You read today. I'm so proud.") end,
          sub = function() return _("Of me, mostly.") end },
        { mood = "party",
          text = function(f)
              local m = minutes(f)
              return string.format(N_("%d minute read! The crowd goes wild.",
                  "%d minutes read! The crowd goes wild.", m), m)
          end,
          sub = function() return _("The crowd is me. I'm wild.") end },
    },
    books_year = {
        { mood = "cheer",
          text = function(f)
              return string.format(N_("%d book! I'd have a sash by now.",
                  "%d books! I'd have a sash by now.", f.books_year), f.books_year)
          end,
          sub = function() return _("And a tiara. Just saying.") end },
    },
    book_progress = {
        { mood = "curious", text = function(f) return string.format(_("%s? Is there a cat in it?"), f.book.title) end,
          sub = function() return _("There should be. A princess.") end },
    },
    book_waiting = {
        { mood = "sad", text = function(f) return string.format(_("You abandoned %s. Like me."), f.book.title) end,
          sub = function() return _("For three minutes. I remember.") end },
    },
    goal_day = {
        { mood = "party", text = function() return _("Goal reached! Do we need a speech?") end,
          sub = function() return _("I'll do the speech.") end },
    },
    monday = {
        { mood = "grumpy", text = function() return _("Monday. I don't do Mondays.") end,
          sub = function() return _("I have people for that.") end },
    },
    weekend = {
        { mood = "cheer", text = function() return _("Weekend! Perfect for a photo shoot.") end,
          sub = function() return _("You read. I'll pose.") end },
    },
    anytime = {
        { mood = "love", text = function() return _("Do you think I'm pretty? Correct.") end,
          sub = function() return _("Moving on.") end },
        { mood = "surprised", text = function() return _("Mongo, NO. Not the bookmarks.") end,
          sub = function() return _("Sorry. He's a growing boy.") end },
    },
})

-- Tulu.

voice("tulu", {
    greet_morning = {
        { mood = "happy", text = function() return _("Dawn tide. Good morning.") end,
          sub = function() return _("The deep stirs.") end },
        { mood = "neutral", text = function() return _("Morning. The stars are not yet right.") end,
          sub = function() return _("So, reading it is.") end },
    },
    greet_afternoon = {
        { mood = "happy", text = function() return _("Afternoon currents are calm.") end,
          sub = function() return _("Good depth for reading.") end },
        { mood = "sleepy", text = function() return _("I dreamt of my sunken city again.") end,
          sub = function() return _("It had a lovely library.") end },
    },
    greet_evening = {
        { mood = "curious", text = function() return _("Evening. The light sinks.") end,
          sub = function() return _("Time to go deeper.") end },
        { mood = "playful", text = function() return _("Evening. Your sanity looks well.") end,
          sub = function() return _("Let's spend a little of it.") end },
    },
    greet_night = {
        { mood = "sleepy", text = function() return _("Night. The abyss hums.") end,
          sub = function() return _("Read me a page.") end },
        { mood = "shy", text = function() return _("Night. Something vast stirs.") end,
          sub = function() return _("It's me. I'm stretching.") end },
    },
    streak = {
        { mood = "happy", text = function() return _("Your streak runs deep.") end,
          sub = function() return _("Steady as the tide.") end },
        { mood = "curious",
          text = function(f)
              return string.format(N_("%d day. Even cultists take breaks.",
                  "%d days. Even cultists take breaks.", f.streak), f.streak)
          end,
          sub = function() return _("You, apparently, don't.") end },
    },
    streak_paused = {
        { mood = "neutral", text = function() return _("Your streak sank. Things do.") end,
          sub = function() return _("Some rise again. Ask me.") end },
    },
    today = {
        { mood = "love", text = function() return _("You read today. The deep smiles.") end },
        { mood = "happy",
          text = function(f)
              local m = minutes(f)
              return string.format(N_("%d minute read. An eyeblink, to me.",
                  "%d minutes read. An eyeblink, to me.", m), m)
          end,
          sub = function() return _("A very good eyeblink.") end },
    },
    books_year = {
        { mood = "curious",
          text = function(f)
              return string.format(N_("%d book this year. A forbidden one?",
                  "%d books this year. Any forbidden?", f.books_year), f.books_year)
          end,
          sub = function() return _("Pity.") end },
    },
    book_progress = {
        { mood = "curious", text = function(f) return string.format(_("%s. Does anyone go mad?"), f.book.title) end,
          sub = function() return _("Asking for a friend.") end },
    },
    book_waiting = {
        { mood = "sleepy", text = function(f) return string.format(_("%s is waiting. I know how it is."), f.book.title) end,
          sub = function() return _("I waited aeons. It's fine.") end },
    },
    goal_day = {
        { mood = "happy", text = function() return _("Daily goal done. The deep is pleased.") end,
          sub = function() return _("Rarely. Enjoy it.") end },
    },
    monday = {
        { mood = "playful", text = function() return _("Monday. A small, ordinary horror.") end,
          sub = function() return _("I quite like it.") end },
    },
    weekend = {
        { mood = "love", text = function() return _("Weekend. Let's not surface at all.") end,
          sub = function() return _("Leave the shallows to others.") end },
    },
    anytime = {
        { mood = "shy", text = function() return _("Ph'nglui… sorry. Hello.") end,
          sub = function() return _("Old habits.") end },
        { mood = "curious", text = function() return _("I speak many unspeakable tongues.") end,
          sub = function() return _("Your book's one is my favourite.") end },
    },
})

-- Frankie.

voice("frankie", {
    greet_morning = {
        { mood = "cheer", text = function() return _("Good morning! All parts present.") end,
          sub = function() return _("Stitches tight.") end },
        { mood = "surprised", text = function() return _("Morning! My left hand woke up first.") end,
          sub = function() return _("It wasn't always mine.") end },
    },
    greet_afternoon = {
        { mood = "happy", text = function() return _("Afternoon! I'm holding together.") end,
          sub = function() return _("Read with me?") end },
        { mood = "party", text = function() return _("Afternoon! I'm full of energy.") end,
          sub = function() return _("Literally. There was lightning.") end },
    },
    greet_evening = {
        { mood = "happy", text = function() return _("Evening! Patching up the day.") end,
          sub = function() return _("A chapter helps.") end },
        { mood = "curious", text = function() return _("Evening! I learned to talk from books.") end,
          sub = function() return _("Hence the vocabulary.") end },
    },
    greet_night = {
        { mood = "sleepy", text = function() return _("Night! Seams are sleepy.") end,
          sub = function() return _("Zzz. Stitch.") end },
        { mood = "playful", text = function() return _("Night! Dark and stormy. My kind.") end,
          sub = function() return _("Read me something gothic.") end },
    },
    streak = {
        { mood = "cheer", text = function() return _("Streak! I'm all stitched up.") end,
          sub = function() return _("Don't let it fray.") end },
        { mood = "happy",
          text = function(f)
              return string.format(N_("%d day! More consistent than me.",
                  "%d days! More consistent than me.", f.streak), f.streak)
          end,
          sub = function() return _("I'm six different people.") end },
    },
    streak_paused = {
        { mood = "cheer", text = function() return _("Streak broken? I can sew that.") end,
          sub = function() return _("I'm very good at it.") end },
    },
    today = {
        { mood = "party", text = function() return _("You read today! Hooray!") end,
          sub = function() return _("Gold star, hand-sewn.") end },
        { mood = "love",
          text = function(f)
              local m = minutes(f)
              return string.format(N_("%d minute read! Both hearts swell.",
                  "%d minutes read! Both hearts swell.", m), m)
          end,
          sub = function() return _("Long story.") end },
    },
    books_year = {
        { mood = "happy",
          text = function(f)
              return string.format(N_("%d book this year! Like my brain.",
                  "%d books this year! Like my brain.", f.books_year), f.books_year)
          end,
          sub = function() return _("Assembled from many sources.") end },
    },
    book_progress = {
        { mood = "curious", text = function(f) return string.format(_("%s! Is the monster misunderstood?"), f.book.title) end,
          sub = function() return _("They usually are.") end },
    },
    book_waiting = {
        { mood = "sad", text = function(f) return string.format(_("%s feels abandoned."), f.book.title) end,
          sub = function() return _("Trust me. I know the feeling.") end },
    },
    goal_day = {
        { mood = "party", text = function() return _("Goal reached! IT'S ALIVE!") end,
          sub = function() return _("Sorry. Family motto.") end },
    },
    monday = {
        { mood = "cheer", text = function() return _("Monday! A fresh start. I love those.") end,
          sub = function() return _("I've had a few.") end },
    },
    weekend = {
        { mood = "playful", text = function() return _("Weekend! Read till my bolts hum.") end,
          sub = function() return _("Yes, they're real bolts.") end },
    },
    anytime = {
        { mood = "curious", text = function() return _("I read Paradise Lost once.") end,
          sub = function() return _("It explained a lot.") end },
        { mood = "shy", text = function() return _("My stitches itch when you're away.") end,
          sub = function() return _("Science can't explain it.") end },
    },
})

-- Vlad.

voice("vlad", {
    greet_morning = {
        { mood = "sleepy", text = function() return _("Morning. The sun is… rude.") end,
          sub = function() return _("Close the curtains. Read.") end },
        { mood = "grumpy", text = function() return _("Morning. Who opened the blinds?") end,
          sub = function() return _("I'll be in the shade. Reading.") end },
    },
    greet_afternoon = {
        { mood = "happy", text = function() return _("Afternoon. I'm hiding indoors.") end,
          sub = function() return _("A book keeps me company.") end },
        { mood = "sleepy", text = function() return _("Afternoon. I'm technically asleep.") end,
          sub = function() return _("Turn pages softly.") end },
    },
    greet_evening = {
        { mood = "happy", text = function() return _("Evening. At last.") end,
          sub = function() return _("My favourite hour.") end },
        { mood = "love", text = function() return _("Welcome. Enter freely.") end,
          sub = function() return _("And of your own will.") end },
    },
    greet_night = {
        { mood = "love", text = function() return _("Night. Now we live.") end,
          sub = function() return _("Read until dawn.") end },
        { mood = "curious", text = function() return _("Listen. The children of the night.") end,
          sub = function() return _("What music they make.") end },
    },
    streak = {
        { mood = "happy", text = function() return _("A streak. How eternal.") end,
          sub = function() return _("I approve of habits.") end },
        { mood = "neutral",
          text = function(f)
              return string.format(N_("%d day. Centuries start like this.",
                  "%d days. Centuries start like this.", f.streak), f.streak)
          end,
          sub = function() return _("Trust me.") end },
    },
    streak_paused = {
        { mood = "sad", text = function() return _("Your streak vanished. Like my reflection.") end,
          sub = function() return _("One gets used to it.") end },
    },
    today = {
        { mood = "love", text = function() return _("Reading done today. Elegant.") end,
          sub = function() return _("I'm almost warm.") end },
        { mood = "happy",
          text = function(f)
              local m = minutes(f)
              return string.format(N_("%d minute read. Delicious.", "%d minutes read. Delicious.", m), m)
          end,
          sub = function() return _("I mean the prose.") end },
    },
    books_year = {
        { mood = "neutral",
          text = function(f)
              return string.format(N_("%d book this year. A fine start.",
                  "%d books this year. A fine start.", f.books_year), f.books_year)
          end,
          sub = function() return _("I'm on my fourth century.") end },
    },
    book_progress = {
        { mood = "curious", text = function(f) return string.format(_("%s. Is there garlic in it?"), f.book.title) end,
          sub = function() return _("I'll skip those pages.") end },
    },
    book_waiting = {
        { mood = "sleepy", text = function(f) return string.format(_("%s waits. As do I."), f.book.title) end,
          sub = function() return _("I've practised for centuries.") end },
    },
    goal_day = {
        { mood = "happy", text = function() return _("Goal reached. Sinister efficiency.") end,
          sub = function() return _("I admire it.") end },
    },
    monday = {
        { mood = "grumpy", text = function() return _("Monday. A dreadful invention.") end,
          sub = function() return _("Even I won't bite it.") end },
    },
    weekend = {
        { mood = "love", text = function() return _("Weekend. Late nights at last.") end,
          sub = function() return _("Join me. Bring a book.") end },
    },
    anytime = {
        { mood = "shy", text = function() return _("I've never seen myself read.") end,
          sub = function() return _("Mirrors. Long story.") end },
        { mood = "playful", text = function() return _("Your neck is safe. Your book isn't.") end,
          sub = function() return _("I'll be borrowing it.") end },
    },
})

-- Sholmes.

voice("sholmes", {
    greet_morning = {
        { mood = "curious", text = function() return _("Morning. You slept six hours.") end,
          sub = function() return _("A guess. Am I wrong?") end },
        { mood = "neutral", text = function() return _("Morning. Two coffees already.") end,
          sub = function() return _("Your page turns gave it away.") end },
    },
    greet_afternoon = {
        { mood = "curious", text = function() return _("Afternoon. The case awaits.") end,
          sub = function() return _("Open the book.") end },
        { mood = "playful", text = function() return _("Afternoon. You've just had lunch.") end,
          sub = function() return _("Crumbs on the screen.") end },
    },
    greet_evening = {
        { mood = "curious", text = function() return _("Evening. Time for a quiet case.") end,
          sub = function() return _("Of pages.") end },
        { mood = "cheer", text = function() return _("Evening. The game is afoot.") end,
          sub = function() return _("Or rather, the book is.") end },
    },
    greet_night = {
        { mood = "surprised", text = function() return _("Night. Why are you awake?") end,
          sub = function() return _("A good book, I deduce.") end },
        { mood = "shy", text = function() return _("Night. Someone sleeps nearby.") end,
          sub = function() return _("You turn pages so softly.") end },
    },
    streak = {
        { mood = "happy", text = function() return _("Streak noted. A pattern!") end,
          sub = function() return _("Habits reveal character.") end },
        { mood = "curious",
          text = function(f)
              return string.format(N_("%d day. Data at last.", "%d days. Data at last.", f.streak), f.streak)
          end,
          sub = function() return _("No bricks without clay.") end },
    },
    streak_paused = {
        { mood = "neutral", text = function() return _("Your streak stopped. No foul play.") end,
          sub = function() return _("A busy week, I deduce.") end },
    },
    today = {
        { mood = "happy", text = function() return _("Your bookmark moved. I noticed.") end,
          sub = function() return _("Elementary.") end },
        { mood = "playful",
          text = function(f)
              local m = minutes(f)
              return string.format(N_("%d minute read. You skipped a page.",
                  "%d minutes read. You skipped a page.", m), m)
          end,
          sub = function() return _("I'll say nothing. Mostly.") end },
    },
    books_year = {
        { mood = "neutral",
          text = function(f)
              return string.format(N_("%d book this year. I solved it.",
                  "%d books this year. I solved each.", f.books_year), f.books_year)
          end,
          sub = function() return _("I read the last page first.") end },
    },
    book_progress = {
        { mood = "curious",
          text = function(f) return string.format(_("%s, %d%%. I know the ending."), f.book.title, f.book.percent) end,
          sub = function() return _("I won't tell. Probably.") end },
    },
    book_waiting = {
        { mood = "curious", text = function(f) return string.format(_("%s, untouched. The dust agrees."), f.book.title) end,
          sub = function() return _("A cold case.") end },
    },
    goal_day = {
        { mood = "happy", text = function() return _("Goal reached. You have a method.") end,
          sub = function() return _("I've been studying it.") end },
    },
    monday = {
        { mood = "curious", text = function() return _("Monday. A day of small mysteries.") end,
          sub = function() return _("Mostly missing socks.") end },
    },
    weekend = {
        { mood = "grumpy", text = function() return _("Weekend. No cases. Dreadfully dull.") end,
          sub = function() return _("Read me something thrilling.") end },
    },
    anytime = {
        { mood = "curious", text = function() return _("You have been reading, I perceive.") end,
          sub = function() return _("The way you hold the device.") end },
        { mood = "neutral", text = function() return _("Rule out the impossible, and…") end,
          sub = function() return _("…what remains is a good book.") end },
    },
})

-- Argos.

voice("argos", {
    greet_morning = {
        { mood = "cheer", text = function() return _("Good morning! Good morning!") end,
          sub = function() return _("Read, then walk?") end },
        { mood = "party", text = function() return _("MORNING! Is it a walk? A book?") end,
          sub = function() return _("Either! Both! Hi!") end },
    },
    greet_afternoon = {
        { mood = "cheer", text = function() return _("Afternoon! Are we reading?") end,
          sub = function() return _("I'm ready!") end },
        { mood = "playful", text = function() return _("Afternoon! I found a stick!") end,
          sub = function() return _("It's a bookmark now.") end },
    },
    greet_evening = {
        { mood = "love", text = function() return _("Evening! Cuddle and read?") end,
          sub = function() return _("I saved you a spot.") end },
        { mood = "happy", text = function() return _("Evening! I warmed your seat!") end,
          sub = function() return _("It only smells a little.") end },
    },
    greet_night = {
        { mood = "sleepy", text = function() return _("Night! Sleepy pup here.") end,
          sub = function() return _("Read a little more?") end },
        { mood = "surprised", text = function() return _("Night! I heard a noise! It was me.") end,
          sub = function() return _("Read so I calm down.") end },
    },
    streak = {
        { mood = "party", text = function() return _("Streak! You never skip!") end,
          sub = function() return _("Good friend!") end },
        { mood = "cheer",
          text = function(f)
              return string.format(N_("%d day! Is that a lot? It feels a lot!",
                  "%d days! Is that a lot? It feels a lot!", f.streak), f.streak)
          end,
          sub = function() return _("I can't count. I'm proud!") end },
    },
    streak_paused = {
        { mood = "curious", text = function() return _("The streak ran off! I'll find it!") end,
          sub = function() return _("Finding is my thing!") end },
    },
    today = {
        { mood = "party", text = function() return _("You read today! Yay!") end,
          sub = function() return _("I wagged the whole time.") end },
        { mood = "happy",
          text = function(f)
              local m = minutes(f)
              return string.format(N_("%d minute! I sat still the whole time!",
                  "%d minutes! I sat still the whole time!", m), m)
          end,
          sub = function() return _("Almost the whole time!") end },
    },
    books_year = {
        { mood = "playful",
          text = function(f)
              return string.format(N_("%d book! Can I chew the finished one?",
                  "%d books! Can I chew the finished ones?", f.books_year), f.books_year)
          end,
          sub = function() return _("Just the corners?") end },
    },
    book_progress = {
        { mood = "curious", text = function(f) return string.format(_("%s! Does the dog live?"), f.book.title) end,
          sub = function() return _("Please say the dog lives.") end },
    },
    book_waiting = {
        { mood = "love", text = function(f) return string.format(_("%s is waiting. I know waiting!"), f.book.title) end,
          sub = function() return _("I once waited twenty years.") end },
    },
    goal_day = {
        { mood = "party", text = function() return _("Goal reached! Treat? Treat for you?") end,
          sub = function() return _("I'll hold it for you.") end },
    },
    monday = {
        { mood = "cheer", text = function() return _("Monday! I love Mondays!") end,
          sub = function() return _("I love all the days!") end },
    },
    weekend = {
        { mood = "party", text = function() return _("Weekend! All day together!") end,
          sub = function() return _("Book, walk, book, walk!") end },
    },
    anytime = {
        { mood = "happy", text = function() return _("I brought you your book!") end,
          sub = function() return _("It's a bit wet. Sorry.") end },
        { mood = "love", text = function() return _("Who's a good reader? YOU ARE!") end,
          sub = function() return _("Yes you are!") end },
    },
})

-- Hazel.

voice("hazel", {
    greet_morning = {
        { mood = "cheer", text = function() return _("Good morning! A fresh spell awaits.") end,
          sub = function() return _("It's called reading.") end },
        { mood = "playful", text = function() return _("Morning! I turned the alarm into a toad.") end,
          sub = function() return _("It's much quieter now.") end },
    },
    greet_afternoon = {
        { mood = "happy", text = function() return _("Afternoon! The cauldron's quiet.") end,
          sub = function() return _("Time for a chapter.") end },
        { mood = "shy", text = function() return _("Afternoon! The cat's been a crow all day.") end,
          sub = function() return _("Long story. Read?") end },
    },
    greet_evening = {
        { mood = "love", text = function() return _("Evening! The stars are early.") end,
          sub = function() return _("Perfect for reading.") end },
        { mood = "happy", text = function() return _("Evening! The candles lit themselves.") end,
          sub = function() return _("I've been practising.") end },
    },
    greet_night = {
        { mood = "sleepy", text = function() return _("Night! My hat's drooping.") end,
          sub = function() return _("One more page, one more spell.") end },
        { mood = "love", text = function() return _("Night! Broom parked, hat off.") end,
          sub = function() return _("Story time.") end },
    },
    streak = {
        { mood = "cheer", text = function() return _("Your streak is enchanted.") end,
          sub = function() return _("Don't break the spell.") end },
        { mood = "happy",
          text = function(f)
              return string.format(N_("%d day! A proper ritual now.", "%d days! A proper ritual now.", f.streak), f.streak)
          end,
          sub = function() return _("Rituals are half of magic.") end },
    },
    streak_paused = {
        { mood = "neutral", text = function() return _("Your streak fizzled. Potions do too.") end,
          sub = function() return _("We just stir again.") end },
    },
    today = {
        { mood = "playful", text = function() return _("You read today! Spell worked.") end,
          sub = function() return _("I'm good at this.") end },
        { mood = "surprised",
          text = function(f)
              local m = minutes(f)
              return string.format(N_("%d minute read! Where did it go?", "%d minutes read! Where did they go?", m), m)
          end,
          sub = function() return _("Books eat time. Old magic.") end },
    },
    books_year = {
        { mood = "cheer",
          text = function(f)
              return string.format(N_("%d book this year! A grimoire's start.",
                  "%d books this year! A whole grimoire.", f.books_year), f.books_year)
          end,
          sub = function() return _("Mine's mostly recipes.") end },
    },
    book_progress = {
        { mood = "curious", text = function(f) return string.format(_("%s! Does the witch win?"), f.book.title) end,
          sub = function() return _("She'd better.") end },
    },
    book_waiting = {
        { mood = "shy", text = function(f) return string.format(_("%s waits. I charmed your place."), f.book.title) end,
          sub = function() return _("The bookmark won't budge.") end },
    },
    goal_day = {
        { mood = "party", text = function() return _("Goal reached! Not a single spell.") end,
          sub = function() return _("Well. Maybe one.") end },
    },
    monday = {
        { mood = "grumpy", text = function() return _("Monday. I tried a spell to skip it.") end,
          sub = function() return _("It came back. They always do.") end },
    },
    weekend = {
        { mood = "happy", text = function() return _("Weekend! Brew tea, read, repeat.") end,
          sub = function() return _("Witch's orders.") end },
    },
    anytime = {
        { mood = "curious", text = function() return _("Every book is a spell, you know.") end,
          sub = function() return _("Read it right and things change.") end },
        { mood = "playful", text = function() return _("My hat's been talking about you.") end,
          sub = function() return _("Nice things. Mostly.") end },
    },
})

return Voices
