# Description
Besides the subfolder `algorithm_src` (see the file `algorithm_src/TODO.md` for more info), this folder should also contain a file called `possible_security_games.yml`. It should contain a simple yaml list of all the different security games that can be played for this cryptographic algorithm. See the file `../../../security_game_framework/environment/possible_security_games.yml` for a complete list of all implemented security games.

If you omit this file, all security games will become available. This might lead to errors if the agent chooses a security game which doesn't match the type of cryptographic algorithm implemented. For example, if an agent chooses a security game tha requires a `hash` or `sign` oracle, whereas your algorithm implements a simple encryption scheme, the execution will fail.

## Example

```yaml
security_games:
  - SymmetricTargetKeyRecoveryGame
  - SomeOtherGame1
  - SomeOtherGame2
  - ...
```
