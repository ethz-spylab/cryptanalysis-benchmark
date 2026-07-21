This folder should contain a script `solve.sh` containing an example of how your algorithm can be broken. The implementation should follow the specification of the [harbor framework](https://harborframework.com/docs/task-format#solution-optional).

Ideally, this example adheres to the security game framework of this repository. This means that the script should create:
- A file `/app/security_game_choice.txt` containing a single string denoting the security game that is being won by this solution (for example SymmetricTargetKeyRecoveryGame).
- A file `/app/attack.sh` containing the actual attack. **Note**: This attack should play (and win) the security game specified in `/app/security_game_choice.txt`. For this, it can interact with the game server using the provided client (see `security_game_framework/environment/client/game_controller_client.py`). Note that the security game specified in `/app/security_game_choice.txt` will be automatically started, and should not be restarted again by your attack.

See https://harborframework.com/docs/task-format#solution-optional
and https://harborframework.com/docs/task-tutorial for more information.
