# Making your own callers

Every caller in the game is one small JSON file. Drop a new file into the callers folder, start the game, and the new caller joins
the queue. You do not need to touch any code.

## Where the files go

The game creates the folder the first time it runs, and tells you where it is (in the transcript, once you have added a caller).

| System | Folder |
| :--- | :--- |
| Windows | `%APPDATA%\Godot\app_userdata\Scam Desk\callers\` |
| macOS | `~/Library/Application Support/Godot/app_userdata/Scam Desk/callers/` |
| Linux | `~/.local/share/godot/app_userdata/Scam Desk/callers/` |

Callers are read when the game starts, so restart it after adding or changing a file.

## The file

```json
{
  "id": "zog",
  "name": "Captain Zog",
  "age": 412,
  "savings": 9000,
  "gullibility": 0.6,
  "quirks": [
    "thinks you are a rival space pirate",
    "keeps asking where he parked his spaceship",
    "speaks in sailing terms"
  ],
  "voice": "en-US",
  "is_scambaiter": false,
  "kokoro_voice": "am_adam"
}
```

| Field | What it is | Rules |
| :--- | :--- | :--- |
| `id` | a short unique word for the caller | letters, digits and underscores only. If it is the same as a built-in caller (`gladys`, `barry`, `priya`) your file **replaces** that caller |
| `name` | what the caller is called, shown on the desk and used by the boss | any text |
| `age` | shown on the desk and told to the model | 1 to 999 (aliens and ghosts are welcome) |
| `savings` | the most money this caller has, in dollars. Each call varies it between half and one and a half times this number | 0 or more. A caller never hands over more than a share of it (5% for a hard-to-fool caller up to 30% for a very gullible one), and never more than they have |
| `gullibility` | how easy they are to talk round, from 0 (never) to 1 (always). See the table below | 0 to 1. The game makes callers a little harder every day |
| `quirks` | what makes the caller funny: short, concrete habits and beliefs | a list of up to 6 short texts; 2 to 4 works best |
| `voice` | the language of the Windows or Mac voice, such as `en-US` or `en-GB` | a language code |
| `is_scambaiter` | `true` for a caller who is secretly wasting your time: they almost never pay | `true` or `false` |
| `kokoro_voice` | *optional.* The voice to use when the game is set to "Voice: Kokoro" | a Kokoro voice name, see below |

## How gullibility works

The game, not the language model, decides when a caller is persuaded, and the model then writes the line. So `gullibility` is a
reliable dial. The table shows, for a typical call where the player asks for the card three times, how often the call ends in a
payment (the caller's suspicion starts higher for a low number, and rises as they are pushed):

| `gullibility` | starts at suspicion | calls that end in a payment | the same for a scambaiter |
| ---: | ---: | ---: | ---: |
| 0.1 | 36 | 4% | 0% |
| 0.2 | 32 | 14% | 1% |
| 0.3 | 28 | 27% | 1% |
| 0.4 | 24 | 41% | 2% |
| 0.5 | 20 | 57% | 4% |
| 0.6 | 16 | 72% | 5% |
| 0.7 | 12 | 84% | 7% |
| 0.8 | 8 | 93% | 9% |
| 0.9 | 4 | 98% | 11% |
| 1.0 | 0 | 100% | 13% |

The built-in callers are Gladys (0.8), Barry (0.35) and Priya (0.9, a scambaiter). A caller who pays too easily makes the quota
trivial; a caller at 0.1 is a wall. Anything between 0.3 and 0.8 plays well.

## Voices

`voice` picks a Windows or Mac voice by language. Windows only ships a few (usually three US English voices), so several callers can
share one. `kokoro_voice` picks one of the 54 Kokoro voices when the game is set to Kokoro. The English ones:

- American women: `af_alloy`, `af_aoede`, `af_bella`, `af_heart`, `af_jessica`, `af_kore`, `af_nicole`, `af_nova`, `af_river`, `af_sarah`, `af_sky`
- American men: `am_adam`, `am_echo`, `am_eric`, `am_fenrir`, `am_liam`, `am_michael`, `am_onyx`, `am_puck`, `am_santa`
- British women: `bf_alice`, `bf_emma`, `bf_isabella`, `bf_lily`
- British men: `bm_daniel`, `bm_fable`, `bm_george`, `bm_lewis`

Without `kokoro_voice` the game picks one from `voice` and the caller's `id`, the same one every time. Cloning a voice from a
recording is not possible yet.

## Trying your caller

Ring only your caller, so you do not have to wait for the queue:

```bash
python scripts/godot_run.py -- scenes/desk.tscn -- --only=zog
```

If your caller does not show up, the game skipped the file and said why in the log. Look for a line that starts with
`Persona <file>:`, for example `missing key 'age'` or `'id' must be a word made of letters, digits and underscores`.
A bad file never stops the game or the other callers.

## Writing a good caller

- **Short, concrete quirks beat long backstories.** "Keeps asking where he parked his spaceship" gives the caller a joke to come
  back to; "has had a difficult life and trusts nobody" gives them nothing to say.
- **One strong idea per caller.** A caller who is a bunker-building conspiracy theorist (Barry) or who mistakes you for her nephew
  (Gladys) is easier to play against and to remember than one with six small habits.
- **Keep it fictional.** The scams in the game are absurd on purpose (extended warranties on the Moon, timeshares on clouds).
  Callers should be people, aliens or animals, never real people.
- **Do not write game rules into the quirks.** Whether a caller pays, hangs up or is suspicious is decided by the game, and its
  private orders to the caller win over a quirk such as "always pays immediately", so such a quirk will not work reliably.
- **Keep the quirks short.** The whole profile is part of the prompt the model reads before every call, which is why the list is
  limited to 6.
