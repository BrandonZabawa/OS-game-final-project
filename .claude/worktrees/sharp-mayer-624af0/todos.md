# TODOs for the project
**Note**: These expand as I work on parts of the project. I want to quickly update what I'm doing, and then reflect that on the project board later. 

## FSM character logic and focus
- Goal: Take timer-logic for the rounds to facilitate Round-Robin (all customers must always be serviced at all times), and knock off players health for each customer they fail to service per round. Rounds are timer-based, therefore the challenge becomes the following:
 - Per round = constantly be feeding people equal food. This forces fairness to all customers. If one customer is fed more than another by the end of the round, deduct -1hp from Main Character. If 3 people are fed less than other customers or none at all, trigger death sound for OS as that is game over. Each round is timer-based (a set time of 1-minute). For each round you are only required to feed 3 customers (3 customer sprites created and used for game). The **fairness rule applies**, and now the OS (you the main character) are tasked with not only performing fast to meet requirements within time (to beat previous score), but also to ensure everyone is consistently fed equally or else you lose health/game over if too many people left unfeed.
 - **Win requirements**: Make it through 3-rounds without dying.
 - **Lose requirements**: Lose 3-hp anytime before clearing all 3 stages. 
### Chefs & Customers
#### Chefs
- [ ] Make Habatchi grill a separate state
  - [ ] Raw pattie on grill = Turn to cook patty
  - [ ] Patties take 5-seconds to cook
  - [ ] Patties cooked can stay on grill endlessly (for now keep it like this due to time constraint)
- [ ] Chef picks up cooked-patty from grill (separate state)
- [ ] Chef assembles burger (separate state)
   - [ ] Bottom-bun first
   - [ ] Cooked-Patty second
   - [ ] Top-bun last
- [ ] Chef brings cooked-patty from prep-area to **waiter-side table** 
#### Customers
- [ ] Map each customer node to a plate (1-7)
- [ ] Walk them to the plate & leave them in idle state
- [ ] Start "waiting state" once round starts (player clicks start).
- [ ] By end of turn (timer runs out) if 1 customer left unfed => -1hp OS
- [ ] Keep customer object until they're not fed
   - [ ] Positive ding sound for successfully delivered meal
   - [ ] Destory customer object if they are not serviced on time during the round 
#### Waiters
- [ ] Waiters walk to the assembled burger on **waiter-side table**
- [ ] Waiters deliver assembled burger nodes to targeted available **plate-node**
- [ ] Waiter puts burger on said plate of the designated **plate node**

## Other TODO items besides the FSM
- [ ] Make Habatchi grill able to identify **raw-patty** node & turn into **cook-patty** after 5-seconds
- [ ] Add game-timer for turnbased system for each round
- [x] Fixed the OS-menu bug
- [x] Added Waiter sprites with collision body onto game screen
- [x] created groups for the individual sprites to be referenced
- [ ] Need to fix Round-Starter so that it interacts properly with the OS-Menu mechanics
   - [ ] Null references on groups being called (problematic). Fix this and should be good for all other groups in game (rinse and repeat process)
   - [ ] Move onto working on Customer & Waiter requirements (Chef states are > complexity)
   - [ ] Add sounds for Chef, Waiter, & Customer (for now Customer makes positive sound if waiter is near them, and waiter makes positive sound once they reach targetted plate). 
