-- dialog.lua — Simple UI
-- Conversation catalogue of the Critter module and the rules that pick an
-- exchange.
--
-- An exchange is { id, when(f, tier), opener(f), options }: the critter opens
-- with a line and the user answers with one of the options. An option is
--   { id, text(f), when?(f, tier), delta, reply }
--   delta   effect of the answer on the critter's mood (mood.lua)
--   accept  true when the answer accepts the challenge on offer (talk.lua)
--   recommend  true when the answer asks for a book suggestion (talk.lua); its
--           reply is then what the critter says when it finds none
--   play    true when the answer starts a game (talk.lua); it has no reply
--   quote   true when the answer asks for a quote (talk.lua); it has no reply
--   reply   { mood, text(f), sub?(f), by_tier? }: what the critter says back,
--           shown as a phrase of the bubble. `by_tier[tier]` replaces the
--           fields it sets for a critter in that mood tier (`sub = false`
--           drops the second line).
-- `f` are the facts about the moment (see phrases.lua) and `tier` is the mood
-- tier (see mood.lua).
--
-- Voice: a tiny critter living on the shelf, dry and warm, never sarcastic with
-- the user. Its humour comes from its size and home (bookmark as a blanket, the
-- lamp, the shelf) and from the reading facts, not from stock quips; at most
-- three jokes about its size, and no recurring food gags.
-- Writing rules:
--   - Every answer of an exchange fits every opener variant, since 2-3 are
--     dealt at random.
--   - A reply answers the option that was chosen; `sub` carries the punchline
--     and is left out when it adds nothing.
--   - A tier changes the attitude, not the volume: grumpy is terse but fair,
--     meh tired, okay the base, happy warmer, radiant affectionate. Override a
--     tier only where it adds something.
--   - `delta` runs from -2 to +3: +2/+3 warm or engaged, +1 playful, 0 neutral,
--     -1 a brush-off. A declined answer costs mood but gets a gracious reply.
--   - Lines stay short (about 42 characters, 32 for `sub`) and free of puns that
--     only work in English.

local Deck = require("infra/sui_deck")
local _    = require("infra/sui_i18n").translate
local N_   = require("infra/sui_i18n").ngettext

local Dialog = {}

Dialog.TIERS = { "grumpy", "meh", "okay", "happy", "radiant" }

Dialog.DECK_KEY = "simpleui_critter_dialog_deck"

-- Options offered at most, and fewest an exchange needs to be offered.
local MAX_OPTIONS = 3
local MIN_OPTIONS = 2

-- Today's figures are only offered once the statistics are fresh: on the first
-- paint after a return they may be from a past day.
local function readToday(f) return f.stats_fresh == true and (f.today_pages or 0) >= 1 end
local function nothingToday(f)
    return f.stats_fresh == true and f.today_secs == 0 and f.period ~= "morning"
end

-- Answer that turns a suggestion down.
local function notNow() return _("Not now") end

-- What the critter says when a book suggestion finds no unopened book.
local NO_BOOK_REPLY = {
    mood = "surprised",
    text = function() return _("You've opened every book you own.") end,
    sub  = function() return _("Impressive. And a bit worrying.") end,
    by_tier = {
        grumpy  = { mood = "grumpy", text = function() return _("Not one unopened book. Show-off.") end, sub = false },
        happy   = { mood = "cheer",  text = function() return _("Every book opened! Look at you!") end, sub = false },
        radiant = { mood = "love",   text = function() return _("You've opened them all. I'm so proud.") end, sub = false },
    },
}

-- What the critter says when the user turns a book suggestion down.
local LATER_REPLY = {
    mood = "playful",
    text = function() return _("Okay. They'll wait.") end,
    by_tier = {
        grumpy  = { mood = "grumpy", text = function() return _("Fine. The books can wait. So can I.") end },
        happy   = { mood = "cheer",  text = function() return _("No rush. The shelf isn't going anywhere.") end },
        radiant = { mood = "love",   text = function() return _("Whenever you're ready.") end },
    },
}

-- What the critter says when the user turns a game or a quote down.
local NOT_NOW_REPLY = {
    mood = "shy",
    text = function() return _("Okay. Another time.") end,
    by_tier = {
        grumpy = { mood = "grumpy", text = function() return _("Fine. More room for me.") end },
    },
}

Dialog.EXCHANGES = {
    -- General.
    { id = "question",
      when   = function() return true end,
      opener = function(f)
          if f.user_name then
              return string.format(_("Psst, %s. Can I ask you something?"), f.user_name)
          end
          return _("Psst. Can I ask you something?")
      end,
      options = {
          { id = "of_course", delta = 2,
            text  = function() return _("Of course.") end,
            reply = {
                mood = "curious",
                text = function() return _("When you close a book, do the characters wait?") end,
                sub  = function() return _("I'd hate to keep them waiting.") end,
                by_tier = {
                    radiant = { mood = "love", text = function() return _("Can I stay up while you read tonight?") end,
                                sub = false },
                },
            } },
          { id = "about_books", delta = 1,
            text  = function() return _("Is it about books?") end,
            reply = {
                mood = "playful",
                text = function() return _("Everything is about books.") end,
                sub  = function() return _("Eventually.") end,
            } },
          { id = "small_one", delta = 0,
            text  = function() return _("Only a small one.") end,
            reply = {
                mood = "playful",
                text = function() return _("I only have small ones.") end,
                sub  = function() return _("Look at me.") end,
            } },
          { id = "not_now", delta = -1,
            text  = function() return _("Not now.") end,
            reply = {
                mood = "shy",
                text = function() return _("Saving it for later, then.") end,
                by_tier = {
                    grumpy = { mood = "grumpy", text = function() return _("Fine. It'll keep.") end },
                },
            } },
      } },

    { id = "lonely_books",
      when   = function() return true end,
      opener = function() return _("Do you think books get lonely?") end,
      options = {
          { id = "you_lonely", delta = 3,
            text  = function() return _("Do you get lonely?") end,
            reply = {
                mood = "shy",
                text = function() return _("Not when you're reading.") end,
                sub  = function() return _("I can hear the pages.") end,
                by_tier = {
                    grumpy = { text = function() return _("A little. Thanks for asking.") end, sub = false },
                },
            } },
          { id = "unread", delta = 2,
            text  = function() return _("The unread ones, maybe.") end,
            reply = {
                mood = "sad",
                text = function() return _("I visit them at night.") end,
                sub  = function() return _("Someone has to.") end,
                by_tier = {
                    happy  = { mood = "love", text = function() return _("Then let's pick one to visit.") end, sub = false },
                    grumpy = { mood = "grumpy", text = function() return _("Great. Now I'll worry all night.") end,
                               sub = false },
                },
            } },
          { id = "looked_after", delta = 1,
            text  = function() return _("Mine are well looked after.") end,
            reply = {
                mood = "happy",
                text = function() return _("I've noticed. Not a speck of dust.") end,
                sub  = function() return _("Almost.") end,
            } },
          { id = "no_feelings", delta = -1,
            text  = function() return _("Books don't have feelings.") end,
            reply = {
                mood = "surprised",
                text = function() return _("Tell that to the ending of that one book.") end,
                sub  = function() return _("You know which one.") end,
                by_tier = {
                    radiant = { mood = "playful", text = function() return _("Shh. They can hear you.") end, sub = false },
                },
            } },
      } },

    { id = "found",
      when   = function() return true end,
      opener = function() return _("I found something between the pages.") end,
      options = {
          { id = "what", delta = 2,
            text  = function() return _("What was it?") end,
            reply = {
                mood = "curious",
                text = function() return _("An old bus ticket.") end,
                sub  = function() return _("This book has been places.") end,
            } },
          { id = "my_bookmark", delta = 1,
            text  = function() return _("Was it my bookmark?") end,
            reply = {
                mood = "shy",
                text = function() return _("Oh. I was using it as a blanket.") end,
                sub  = function() return _("I'll give it back. Warm.") end,
                by_tier = {
                    grumpy = { mood = "grumpy", text = function() return _("Yes. I'll sleep on the cover, then.") end,
                               sub = false },
                },
            } },
          { id = "leave_it", delta = 0,
            text  = function() return _("Leave it where it is.") end,
            reply = {
                mood = "happy",
                text = function() return _("Done. It was holding someone's place.") end,
            } },
          { id = "throw_away", delta = -1,
            text  = function() return _("Throw it away.") end,
            reply = {
                mood = "surprised",
                text = function() return _("Never. Things in books are clues.") end,
            } },
      } },

    { id = "what_book",
      when   = function() return true end,
      opener = function() return _("If I were in a book, what kind would it be?") end,
      options = {
          { id = "adventure", delta = 2,
            text  = function() return _("An adventure.") end,
            reply = {
                mood = "cheer",
                text = function() return _("Small critter, tall shelf, very long ladder.") end,
                by_tier = {
                    radiant = { mood = "party", text = function() return _("A map! A sword! A tiny backpack!") end },
                },
            } },
          { id = "cosy", delta = 2,
            text  = function() return _("A cosy one.") end,
            reply = {
                mood = "happy",
                text = function() return _("Tea, a blanket and nothing bad happening.") end,
                sub  = function() return _("Perfect.") end,
                by_tier = {
                    meh = { mood = "sleepy", text = function() return _("A cosy one. Mostly naps.") end, sub = false },
                },
            } },
          { id = "mystery", delta = 1,
            text  = function() return _("A mystery.") end,
            reply = {
                mood = "curious",
                text = function() return _("The case of the missing bookmark.") end,
                sub  = function() return _("I have a suspect.") end,
            } },
          { id = "short", delta = 0,
            text  = function() return _("A very short one.") end,
            reply = {
                mood = "playful",
                text = function() return _("Short books are the best ones.") end,
                sub  = function() return _("Ask anyone my size.") end,
            } },
      } },

    { id = "reading_spot",
      when   = function() return true end,
      opener = function() return _("Where do you like to read the most?") end,
      options = {
          { id = "anywhere", delta = 2,
            text  = function() return _("Anywhere I can.") end,
            reply = {
                mood = "cheer",
                text = function() return _("Queues, buses, kitchens. I've seen you.") end,
                by_tier = {
                    radiant = { mood = "love", text = function() return _("That's my favourite kind of reader.") end },
                },
            } },
          { id = "on_the_go", delta = 2,
            text  = function() return _("On the go.") end,
            reply = {
                mood = "curious",
                text = function() return _("Reading and travelling at once.") end,
                sub  = function() return _("Twice the places.") end,
            } },
          { id = "sofa", delta = 1,
            text  = function() return _("On the sofa.") end,
            reply = {
                mood = "happy",
                text = function() return _("Sofas were invented for books.") end,
                sub  = function() return _("Sitting came later.") end,
            } },
          { id = "bed", delta = 1,
            text  = function() return _("In bed.") end,
            reply = {
                mood = "sleepy",
                text = function() return _("Careful. Books fall on faces.") end,
                sub  = function() return _("I speak from experience.") end,
            } },
      } },

    { id = "last_page",
      when   = function() return true end,
      opener = function() return _("Be honest: do you read the last page first?") end,
      options = {
          { id = "never", delta = 2,
            text  = function() return _("Never!") end,
            reply = {
                mood = "cheer",
                text = function() return _("A purist. I knew I liked you.") end,
                by_tier = {
                    grumpy  = { mood = "grumpy", text = function() return _("Good. Some rules matter.") end },
                    radiant = { mood = "love",   text = function() return _("I knew it. The good kind of reader.") end },
                },
            } },
          { id = "nervous", delta = 1,
            text  = function() return _("Only when I'm nervous.") end,
            reply = {
                mood = "shy",
                text = function() return _("Same. I check that the dog survives.") end,
                sub  = function() return _("Every time.") end,
            } },
          { id = "sometimes", delta = 1,
            text  = function() return _("Sometimes.") end,
            reply = {
                mood = "playful",
                text = function() return _("Your secret is safe with the shelf.") end,
            } },
          { id = "always", delta = 0,
            text  = function() return _("Always.") end,
            reply = {
                mood = "surprised",
                text = function() return _("Bold. You like to know who makes it.") end,
                sub  = function() return _("I won't tell anyone.") end,
                by_tier = {
                    radiant = { mood = "playful", text = function() return _("Chaos. I respect it.") end, sub = false },
                },
            } },
      } },

    -- Time.
    { id = "time_of_day",
      when   = function() return true end,
      opener = function(f)
          if f.period == "morning" then return _("Morning! How did you sleep?") end
          if f.period == "afternoon" then return _("How's the afternoon going?") end
          if f.period == "evening" then return _("How was your day?") end
          return _("Still up? How was your day?")
      end,
      options = {
          { id = "good", delta = 2,
            text  = function() return _("Pretty good.") end,
            reply = {
                mood = "happy",
                text = function() return _("Good. Let's keep it that way.") end,
                sub  = function() return _("A chapter helps.") end,
                by_tier = {
                    radiant = { mood = "cheer", text = function() return _("I had a feeling it would be.") end,
                                sub = false },
                },
            } },
          { id = "could_be_better", delta = 1,
            text  = function() return _("Could be better.") end,
            reply = {
                mood = "shy",
                text = function() return _("Then let's end it with a good chapter.") end,
                sub  = function() return _("Books are good at that.") end,
                by_tier = {
                    happy = { mood = "love", text = function() return _("Then you get the comfiest book tonight.") end,
                              sub = false },
                },
            } },
          { id = "tiring", delta = 1,
            text  = function() return _("Tiring.") end,
            reply = {
                mood = "sleepy",
                text = function() return _("Then read something easy.") end,
                sub  = function() return _("Nothing with maps.") end,
            } },
          { id = "rather_not", delta = -1,
            text  = function() return _("I'd rather not talk.") end,
            reply = {
                mood = "shy",
                text = function() return _("Okay. I'll just sit here.") end,
                sub  = function() return _("Quietly.") end,
            } },
      } },

    { id = "weekday",
      when   = function() return true end,
      opener = function(f)
          if f.weekday == 1 or f.weekday == 7 then
              return string.format(_("It's %s. Reading day, surely?"), f.weekday_name)
          end
          return string.format(_("It's %s. Any reading planned?"), f.weekday_name)
      end,
      options = {
          { id = "every_day", delta = 2,
            text  = function() return _("Every day is a reading day.") end,
            reply = {
                mood = "cheer",
                text = function() return _("Correct. You get a gold star.") end,
                sub  = function() return _("I'm out of stars. Imagine one.") end,
                by_tier = {
                    grumpy = { mood = "grumpy", text = function() return _("Correct. Don't get smug.") end, sub = false },
                },
            } },
          { id = "few_chapters", delta = 2,
            text  = function() return _("Yes, a few chapters.") end,
            reply = {
                mood = "playful",
                text = function() return _("Perfect. I won't look.") end,
                sub  = function() return _("I'll look.") end,
            } },
          { id = "find_time", delta = 1,
            text  = function() return _("If I find the time.") end,
            reply = {
                mood = "curious",
                text = function() return _("Ten minutes count. I checked.") end,
                sub  = function() return _("I'm the one who counts.") end,
                by_tier = {
                    meh = { mood = "sleepy", text = function() return _("Ten minutes count. Even sleepy ones.") end,
                            sub = false },
                },
            } },
          { id = "not_today", delta = -1,
            text  = function() return _("Not today.") end,
            reply = {
                mood = "shy",
                text = function() return _("That's allowed. Books are patient.") end,
                sub  = function() return _("So am I. Mostly.") end,
            } },
      } },

    -- Reading streak.
    { id = "streak_talk",
      when   = function(f) return f.streak ~= nil and f.streak >= 2 end,
      opener = function(f)
          return string.format(N_("Our streak is at %d day. No pressure.",
              "Our streak is at %d days. No pressure.", f.streak), f.streak)
      end,
      options = {
          { id = "keep_going", delta = 3,
            text  = function() return _("Let's keep it going.") end,
            reply = {
                mood = "cheer",
                text = function() return _("That's the spirit. I'll keep count.") end,
                sub  = function() return _("I love counting.") end,
                by_tier = {
                    happy   = { mood = "party", sub = false,
                                text = function(f) return string.format(_("Day %d, here we come!"), f.streak + 1) end },
                    radiant = { mood = "party", sub = false,
                                text = function(f) return string.format(_("Day %d, here we come!"), f.streak + 1) end },
                    grumpy  = { mood = "grumpy", text = function() return _("Good. I'd hate to start over.") end,
                                sub = false },
                },
            } },
          { id = "really", delta = 1,
            text  = function() return _("No pressure? Really?") end,
            reply = {
                mood = "playful",
                text = function() return _("None at all. I'm just writing it on the wall.") end,
                sub  = function() return _("In big letters.") end,
            } },
          { id = "miss_a_day", delta = 0,
            text  = function() return _("What if I miss a day?") end,
            reply = {
                mood = "curious",
                text = function() return _("Then we start again. I'll still be here.") end,
            } },
          { id = "stop_counting", delta = -1,
            text  = function() return _("Stop counting.") end,
            reply = {
                mood = "shy",
                text = function() return _("Sorry. Counting is how I show I care.") end,
            } },
      } },

    { id = "streak_restart",
      when   = function(f) return f.streak == 0 end,
      opener = function() return _("The streak took a little break.") end,
      options = {
          { id = "restart", delta = 3,
            text  = function() return _("Let's start again today.") end,
            reply = {
                mood = "cheer",
                text = function() return _("Day one. My favourite kind.") end,
                sub  = function() return _("Everything starts here.") end,
                by_tier = {
                    grumpy  = { mood = "grumpy", text = function() return _("Day one. Again. Fine.") end, sub = false },
                    radiant = { mood = "love",   text = function() return _("Day one with you. My favourite.") end,
                                sub = false },
                },
            } },
          { id = "back_soon", delta = 2,
            text  = function() return _("I'll be back soon.") end,
            reply = {
                mood = "shy",
                text = function() return _("I'll keep your place.") end,
                sub  = function() return _("I'm good at that.") end,
            } },
          { id = "needed_rest", delta = 1,
            text  = function() return _("It needed a rest.") end,
            reply = {
                mood = "playful",
                text = function() return _("Fair. Even streaks get tired.") end,
                sub  = function() return _("I nap all the time.") end,
            } },
          { id = "dont_remind", delta = -1,
            text  = function() return _("Don't remind me.") end,
            reply = {
                mood = "shy",
                text = function() return _("Forgotten. What streak?") end,
            } },
      } },

    -- Books this year. "What should I read next?" suggests a book (talk.lua).
    { id = "goal_watching",
      when   = function(f) return f.books_year ~= nil and f.books_year >= 1 and f.goal > 0 end,
      opener = function(f)
          return string.format(N_("%d book this year. How's the goal looking?",
              "%d books this year. How's the goal looking?", f.books_year), f.books_year)
      end,
      options = {
          { id = "on_track", delta = 2,
            text  = function() return _("Right on track.") end,
            reply = {
                mood = "cheer",
                text = function() return _("I knew it. I've seen the shelf.") end,
                by_tier = {
                    meh     = { mood = "happy", text = function() return _("On track. Quietly proud of you.") end },
                    radiant = { mood = "party", text = function() return _("On track! I'm telling the whole shelf.") end },
                },
            } },
          { id = "which_next", delta = 1, recommend = true,
            text  = function() return _("What should I read next?") end,
            reply = NO_BOOK_REPLY },
          { id = "behind", delta = 0,
            text  = function() return _("A bit behind.") end,
            reply = {
                mood = "curious",
                text = function() return _("There's still time. Short books count.") end,
                sub  = function() return _("I checked the rules.") end,
            } },
          { id = "forgot", delta = 0,
            text  = function() return _("I forgot I had one.") end,
            reply = {
                mood = "surprised",
                text = function() return _("It didn't forget you.") end,
                sub  = function() return _("Goals are like that.") end,
            } },
      } },

    -- Today's reading.
    { id = "today_read",
      when   = readToday,
      opener = function(f)
          return string.format(N_("%d page today. Where did it take you?",
              "%d pages today. Where did they take you?", f.today_pages), f.today_pages)
      end,
      options = {
          { id = "far_away", delta = 2,
            text  = function() return _("Somewhere far away.") end,
            reply = {
                mood = "love",
                text = function() return _("Lucky. I've never left this shelf.") end,
                sub  = function() return _("Tell me about it sometime.") end,
                by_tier = {
                    grumpy = { mood = "grumpy", text = function() return _("Lucky. I stayed here. On the shelf.") end,
                               sub = false },
                },
            } },
          { id = "spoilers", delta = 1,
            text  = function() return _("Can't say. Spoilers.") end,
            reply = {
                mood = "playful",
                text = function() return _("Fair. I'll find out myself one day.") end,
            } },
          { id = "nowhere", delta = 0,
            text  = function() return _("Nowhere exciting yet.") end,
            reply = {
                mood = "curious",
                text = function() return _("Some chapters are corridors.") end,
                sub  = function() return _("They lead somewhere.") end,
            } },
      } },

    { id = "not_yet_today",
      when   = nothingToday,
      opener = function() return _("No reading yet today. Shall we fix that?") end,
      options = {
          { id = "right_now", delta = 3,
            text  = function() return _("Yes, right now.") end,
            reply = {
                mood = "cheer",
                text = function() return _("Wonderful. I'll hold the lamp.") end,
                by_tier = {
                    radiant = { mood = "party", text = function() return _("Yes! Lamp on. Pages ready.") end },
                },
            } },
          { id = "later_tonight", delta = 1,
            text  = function() return _("Later tonight.") end,
            reply = {
                mood = "happy",
                text = function() return _("I'll remind you.") end,
                sub  = function() return _("Gently.") end,
            } },
          { id = "not_today", delta = 0,
            text  = function() return _("Not today.") end,
            reply = {
                mood = "shy",
                text = function() return _("That's fine. Rest days count too.") end,
            } },
          { id = "stop_nagging", delta = -1,
            text  = function() return _("Stop nagging.") end,
            reply = {
                mood = "shy",
                text = function() return _("Sorry. I just like it when you read.") end,
            } },
      } },

    -- Affection: the answers are pats, and the reply shows the critter's reaction.
    { id = "pet",
      when   = function() return true end,
      opener = function() return _("It's quiet on the shelf. Pat me?") end,
      options = {
          { id = "pat", delta = 2,
            text  = function() return _("A gentle pat") end,
            reply = {
                mood = "love",
                text = function() return _("Oh. That's nice.") end,
                sub  = function() return _("I'll pretend I didn't need it.") end,
                by_tier = {
                    grumpy  = { mood = "grumpy", text = function() return _("Hm. Fine. That's enough.") end, sub = false },
                    radiant = { mood = "love",   text = function() return _("Best part of my day.") end, sub = false },
                },
            } },
          { id = "scratch", delta = 2,
            text  = function() return _("Scratch its head") end,
            reply = {
                mood = "shy",
                text = function() return _("Right there. A little to the left.") end,
                sub  = function() return _("Perfect.") end,
                by_tier = {
                    grumpy  = { mood = "grumpy", text = function() return _("Left. No, not that left.") end, sub = false },
                    radiant = { mood = "love",   text = function() return _("Don't ever stop.") end, sub = false },
                },
            } },
          { id = "tickle", delta = 1,
            when  = function(_f, tier) return tier ~= "grumpy" end,
            text  = function() return _("Tickle it") end,
            reply = {
                mood = "playful",
                text = function() return _("Hehe! Stop! Don't stop!") end,
                sub  = function() return _("Okay. Stop.") end,
                by_tier = {
                    meh   = { mood = "surprised", text = function() return _("Hey! I was resting.") end,
                              sub = function() return _("…Do it again.") end },
                    happy = { mood = "party", text = function() return _("Ha! You'll pay for this!") end, sub = false },
                },
            } },
          { id = "leave", delta = 0,
            text  = function() return _("Let it be") end,
            reply = {
                mood = "shy",
                text = function() return _("Okay. I'll be here.") end,
                by_tier = {
                    grumpy = { mood = "grumpy", text = function() return _("Good. I like the quiet.") end },
                },
            } },
      } },

    -- Book suggestion: "Yes, pick one" has the conversation suggest an unopened
    -- book (talk.lua); its reply is what the critter says when there is none.
    { id = "read_next",
      when   = function() return true end,
      opener = function() return _("Want me to pick your next book?") end,
      options = {
          { id = "yes", delta = 1, recommend = true,
            text  = function() return _("Yes, pick one") end,
            reply = NO_BOOK_REPLY },
          { id = "later", delta = 0,
            text  = notNow,
            reply = LATER_REPLY },
      } },

    -- Games and quotes: "Let's play" opens the choice of games and "Yes, please"
    -- reads a quote (talk.lua).
    { id = "play",
      when   = function() return true end,
      opener = function() return _("Want to play something?") end,
      options = {
          { id = "yes", delta = 1, play = true,
            text = function() return _("Let's play") end },
          { id = "later", delta = 0,
            text  = notNow,
            reply = NOT_NOW_REPLY },
      } },
    { id = "read_quote",
      when   = function() return true end,
      opener = function() return _("Shall I read you something?") end,
      options = {
          { id = "yes", delta = 1, quote = true,
            text = function() return _("Yes, please") end },
          { id = "later", delta = 0,
            text  = notNow,
            reply = NOT_NOW_REPLY },
      } },

    -- Challenges (challenge.lua): the opener is the offer or the progress, ready
    -- as text in `f.challenge`. Accepting an offer is handled by talk.lua.
    { id = "challenge_offer",
      when   = function(f) return f.challenge ~= nil and f.challenge.offer ~= nil end,
      opener = function(f) return f.challenge.text end,
      options = {
          { id = "accept", delta = 1, accept = true,
            text  = function() return _("Challenge accepted") end,
            reply = {
                mood = "cheer",
                text = function() return _("Deal. I'll keep an eye on it.") end,
                sub  = function() return _("A friendly eye.") end,
                by_tier = {
                    grumpy  = { mood = "grumpy", text = function() return _("Bold. Let's see.") end, sub = false },
                    happy   = { mood = "party",  text = function() return _("Yes! You've got this!") end, sub = false },
                    radiant = { mood = "love",   text = function() return _("I knew you'd say yes.") end, sub = false },
                },
            } },
          { id = "later", delta = 0,
            text  = function() return _("Maybe later") end,
            reply = {
                mood = "playful",
                text = function() return _("The offer stands until midnight.") end,
                by_tier = {
                    grumpy  = { mood = "grumpy", text = function() return _("Suit yourself.") end },
                    radiant = { mood = "shy",    text = function() return _("Of course. No pressure.") end },
                },
            } },
      } },
    { id = "challenge_active",
      when   = function(f) return f.challenge ~= nil and f.challenge.active == true end,
      opener = function(f) return f.challenge.text end,
      options = {
          { id = "on_it", delta = 1,
            text  = function() return _("On it!") end,
            reply = {
                mood = "cheer",
                text = function() return _("Go! I'll be here, counting.") end,
                by_tier = {
                    grumpy  = { mood = "grumpy", text = function() return _("Less talking. More reading.") end },
                    radiant = { mood = "party",  text = function() return _("You're unstoppable today.") end },
                },
            } },
          { id = "tough", delta = 0,
            text  = function() return _("Tough one…") end,
            reply = {
                mood = "curious",
                text = function() return _("One page at a time. They all count.") end,
                by_tier = {
                    happy = { mood = "cheer",  text = function() return _("You can do it. One page at a time.") end },
                    meh   = { mood = "sleepy", text = function() return _("Then slowly. Very slowly.") end },
                },
            } },
      } },
}

-- Options of `exchange` open to `tier` at the facts `f`.
local function eligibleOptions(exchange, f, tier)
    local list = {}
    for _i, option in ipairs(exchange.options) do
        if option.when == nil or option.when(f, tier) then list[#list + 1] = option end
    end
    return list
end

-- What the critter answers `reply` says for a critter in mood tier `tier`.
local function renderReply(reply, f, tier)
    local override = reply.by_tier and reply.by_tier[tier] or {}
    local sub = reply.sub
    if override.sub ~= nil then sub = override.sub end
    return {
        mood = override.mood or reply.mood,
        text = (override.text or reply.text)(f),
        sub  = sub and sub(f) or nil,
    }
end

local function shuffle(list)
    for i = #list, 2, -1 do
        local j = math.random(i)
        list[i], list[j] = list[j], list[i]
    end
    return list
end

--- An exchange for the facts `f` and the mood tier `tier`, or nil when none
--- fits. Returns { id, opener, options } with 2 or 3 options dealt at random
--- ({ id, text, delta, recommend, play, quote, accept, reply = function(tier) -> { text, sub, mood } }), all
--- texts written for `f`. Exchanges are dealt from a deck, so none comes
--- round before the others have been seen.
function Dialog.pick(f, tier)
    local ids, by_id = {}, {}
    for _i, exchange in ipairs(Dialog.EXCHANGES) do
        if exchange.when(f, tier) then
            local options = eligibleOptions(exchange, f, tier)
            if #options >= MIN_OPTIONS then
                ids[#ids + 1] = exchange.id
                by_id[exchange.id] = { exchange = exchange, options = options }
            end
        end
    end
    local id = Deck.pick(Dialog.DECK_KEY, ids)
    if not id then return nil end

    local entry = by_id[id]
    local options = {}
    for _i, option in ipairs(shuffle(entry.options)) do
        if #options == MAX_OPTIONS then break end
        options[#options + 1] = {
            id    = option.id,
            text  = option.text(f),
            delta = option.delta,
            recommend = option.recommend,
            play  = option.play,
            quote = option.quote,
            accept = option.accept,
            reply = function(reply_tier) return renderReply(option.reply, f, reply_tier) end,
        }
    end
    return { id = id, opener = entry.exchange.opener(f), options = options }
end

--- The lines of the second step of a book suggestion for `book` ({ title,
--- authors }) and a critter in mood tier `tier`: { opener, open_text,
--- another_text, later_text, later_reply = { mood, text, sub? } }.
function Dialog.suggestion(book, f, tier)
    local authors = book.authors and book.authors:gsub("\n", ", ")
    local opener = authors and authors ~= ""
        and string.format(_("Try “%s”, by %s."), book.title, authors)
        or string.format(_("Try “%s”."), book.title)
    return {
        opener       = opener,
        open_text    = _("Open it"),
        another_text = _("Another one"),
        later_text   = notNow(),
        later_reply  = renderReply(LATER_REPLY, f, tier),
    }
end

return Dialog
