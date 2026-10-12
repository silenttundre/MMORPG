# Two Player Creative World over LAN

Copy this project to both computers. On each computer, double-click `run_game.bat` (or open `project.godot` with Godot 4.6 and run it).

1. On the first computer, choose **Host game**, create a character, and enter the world.
2. Find the first computer's IPv4 address using `ipconfig` in Command Prompt.
3. On the second computer, choose **Join game**, type the host's IPv4 address, create a character, and enter the world.

Both computers must be on the same local network. The host must allow Godot through Windows Firewall for private networks, or allow inbound **UDP 24567**. One guest can join. Both computers should have the same version of this project.

| Player | Move | Jump | Place block | Remove block | Attack | Shop | Minimap | Balloon |
|---|---|---|---|---|---|---|---|---|
| Player 1 | W A S D or arrow keys | Space | Q | E | R | B | M | F near landing |
| Player 2 | W A S D or arrow keys | Space | Q | E | R | B | M | F near landing |

Each player has their own camera and sees the other character, shared creations, crystals, and score. Blocks are placed in the direction each character last moved and stack up to seven blocks high. No Docker, database, account, or internet connection is required.

The mainland has a central crossroads, pine forest, sunny meadow, rocky highlands, sandy desert, and cemetery. Skeletons guard the cemetery. Two more places sit across gaps: a mountain range with goats, boulders, and two bat caves to the east, and the Wildwood forest with deer, rabbits, and dense trees to the west. Goats, deer, and rabbits are peaceful; skeletons and bats attack. Your current area and coordinates appear at the top right. Crystals are spread across all three places and respawn after each group of 36 is collected.

Walk to a purple balloon landing near either east or west edge of the mainland, then press **F** when the prompt appears. The east balloon floats to the mountains; the west balloon floats to Wildwood. A balloon at each destination returns to the mainland. Flights take about 14 seconds and are free. The other player can see you traveling. If you fall between places, you return to where you last stood safely.

Press **M** to show or hide the upper-right minimap. It shows all three places, balloon landings (purple), obstacles, cemetery and caves, enemies (red), crystals, blocks built by players, your position (white), and the other player's position (orange). North is at the top.

The lower-left bars show both players' health. Press **R** to strike an enemy in front of you; a sword from the shop gives a longer, stronger attack. Defeating an enemy earns one crystal, and enemies return after about 25 seconds. If your health runs out, you respawn on the mainland with full health.

Collect crystals and press **B** to open the shop. Snacks cost 2 crystals, restore 30 health (up to 100), and give a 20-second speed boost. A lantern costs 3 and lights your way; a sword costs 4; speed boots cost 5 and permanently increase walking speed. A bicycle costs 6, a motorbike 9, and a car 12. Buying a vehicle equips it; click an owned vehicle again to ride or park it. Moving bicycles can hurt enemies but riders still take some impact damage; motorbikes hit harder; a moving car runs enemies over without hurting its driver. Vehicles also reduce damage from enemy attacks while stopped. Purchases, health, enemies, and crystal balances are shared over LAN and last for the current host session.
