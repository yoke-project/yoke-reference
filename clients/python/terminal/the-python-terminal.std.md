# The terminal, a reference interface client in Python

| | |
| --- | --- |
| **Feature** | a reference interface client in Python, written against the published Python interface library like anyone's and built from the registry alone: it attaches to a channel named on its command line, or the one a managed interface is handed; draws the picture the channel opens with, one line for each thing the channel sees; sends one command and asks one question if it is told to; and follows the events of its standing subscription, then leaves with a status that tells done from refused |
| **Planning item** | yoke-project/yoke-reference#57 |

## yoke-reference:the-python-terminal.01 — the channel is named one way, and the operations are read

| Field | Value |
| --- | --- |
| **Cites** | specs/90.42 · arch/90-sdks/07 §What each one is · arch/70-interface-surface/01 §Where a channel is bound |
| **Level** | L1 |
| **Method** | test |
| **Not applicable in** | — |
| **Label** | blocking |
| **Precondition** | an environment holding `XDG_RUNTIME_DIR` and `YOKE_SOCKET` |
| **Action** | read command lines naming a channel by instance, by runtime directory, by socket and by none, with a command, a question and a count; and lines that name it twice, name no unit, take no count, or name no option |
| **Expected** | each channel is the address the library computes for it, or the one a managed interface is handed; the command, the question and the count are read as given; every wrong line is refused, saying what is wrong |

## yoke-reference:the-python-terminal.02 — a picture is drawn a line for each thing the channel sees

| Field | Value |
| --- | --- |
| **Cites** | specs/90.42 · arch/90-sdks/07 §What each one is · arch/70-interface-surface/01 §Where a channel is bound |
| **Level** | L1 |
| **Method** | test |
| **Not applicable in** | — |
| **Label** | blocking |
| **Precondition** | a picture holding the instance ready, a unit running with a command and a question addressed to it, and the channel attached |
| **Action** | draw it; draw an event |
| **Expected** | one line each, in the order of the picture: `instance ready`, the unit with its state, commands, questions and streams, and the channel with its projection; the event as its sequence, its type and its subject |

## yoke-reference:the-python-terminal.03 — a channel nobody serves is said, and the status is one

| Field | Value |
| --- | --- |
| **Cites** | specs/90.42 · arch/90-sdks/07 §What each one is · arch/70-interface-surface/01 §Where a channel is bound |
| **Level** | L1 |
| **Method** | test |
| **Not applicable in** | — |
| **Label** | blocking |
| **Precondition** | an address nothing listens at |
| **Action** | run the client against it |
| **Expected** | it says, in one line that begins `terminal:`, that it failed or was refused, and its status is 1 |

## yoke-reference:the-python-terminal.04 — the published Core's channel is attached, drawn, commanded, asked and followed

| Field | Value |
| --- | --- |
| **Cites** | specs/90.42 · arch/70-interface-surface/03 §The opening picture · arch/70-interface-surface/04 §The eleven |
| **Level** | L3 |
| **Method** | test |
| **Not applicable in** | — |
| **Label** | blocking |
| **Precondition** | the host archive the manifest names as latest, authenticated by its digest; an instance holding the Go clock and an attached channel `terminal`; the clock granted its command, its question and its occurrence, and restarted |
| **Action** | run the client against the channel with a command `clock:clock.mark`, a question `clock:clock.now` and one event to follow |
| **Expected** | it says it attached; draws the clock running with `clock.mark` and `clock.now`; reports the command done; answers the question with a time; follows one event of the mark; and leaves with status 0 |

