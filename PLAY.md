# Creative World over LAN

Copy this project to both computers. On each computer, double-click `run_game.bat` (or open `project.godot` with Godot 4.6 and run it).

1. On the first computer, choose **Host game**, create a character, and enter the world.
2. Find the first computer's IPv4 address using `ipconfig` in Command Prompt.
3. On each other computer, choose **Join game**, type the host's IPv4 address, create a character, and enter the world.

All computers must be on the same local network. The host must allow Godot through Windows Firewall for private networks, or allow inbound **UDP 24567**. Up to 31 guests can join one host (32 players total); actual smooth performance depends on the computers and network. Everyone should have the same version of this project.

| Player | Move | Jump / plane climb | Plane descend | Place block | Remove block | Attack | Shop | Minimap | Blueprint | Balloon / workshop |
|---|---|---|---|---|---|---|---|---|---|---|
| Host | W A S D or arrow keys | Space | Shift | Q | E | R | B | M | P | F nearby |
| Every guest | W A S D or arrow keys | Space | Shift | Q | E | R | B | M | P | F nearby |

Each player has their own camera and sees other characters, shared creations, crystals, and scores. Blocks are placed in the direction each character last moved and stack up to seven blocks high. No Docker, database, account, or internet connection is required.

All nine places have larger explorable terrain. The mainland has a central crossroads, pine forest, sunny meadow, rocky highlands, sandy desert, cemetery, and a plane workshop. Skeletons guard the cemetery. Across the gaps are the mountains with goats and bat caves (east), Wildwood with deer and rabbits (west), the Arctic with polar bears and tougher sasquatches (north), and the lake with sharks, peaceful whales, and fish (south). Four further destinations lie diagonally: Crystal Caverns (northwest), Volcano (northeast), Golden Dunes (southwest), and Jungle Ruins (southeast). Your current area and coordinates appear at the top right. Crystals are spread across all nine places and respawn after each group of 36 is collected.

Walk to a purple balloon landing near an edge of the mainland, then press **F** when the prompt appears. The cardinal landings lead to the mountains, Wildwood, Arctic, and lake; the four diagonal landings lead to the four new places. A balloon at each destination returns to the mainland. Flights take about 14 seconds and are free. Other players can see you traveling. If you fall between places, you return to where you last stood safely—unless you are flying the plane.

Press **M** to show or hide the upper-right minimap. It shows all nine places, balloon landings (purple), obstacles, cemetery and caves, enemies (red), crystals, blocks built by players, your position (white), and other players (orange). Plane parts do **not** appear on the minimap; look for their faint glow while exploring. North is at the top.

The lower-left scrollable bars show players' health. Press **R** to strike an enemy in front of you; a sword from the shop gives a longer, stronger attack. Defeating an enemy earns one crystal, and enemies return after about 25 seconds. If your health runs out, you respawn on the mainland with full health.

Collect crystals and press **B** to open the shop. Snacks cost 2 crystals, restore 30 health (up to 100), and give a 20-second speed boost. A lantern costs 3 and lights your way; a sword costs 4; speed boots cost 5 and permanently increase walking speed. A bicycle costs 6, a motorbike 9, and a car 12. A rowboat costs 7 and a speedboat costs 13. You need either boat to cross the lake; the rowboat is slower and offers less protection from sharks, while the speedboat is fast and takes less damage. Sharks defeat an unprotected swimmer in one bite. You cannot park or switch boats while on the water. Buying a vehicle equips it; click an owned vehicle again to ride or park it on shore. Moving bicycles can hurt enemies but riders still take some impact damage; motorbikes hit harder; a moving car runs enemies over without hurting its driver. Vehicles also reduce damage from enemy attacks while stopped. Purchases, health, enemies, and crystal balances are shared over LAN and last for the current host session.

The plane is a separate discovery project. Each of the eight destinations hides one small, softly glowing component, and each player needs to find their own set. The parts remain in place for other players. Buy the **Plane blueprint** for 8 crystals, then press **P** to read its list of components and assembly instructions. It tells you which world contains each part but not its precise location. After collecting all eight, return to the workbench at the mainland crossroads and press **F** to assemble and equip the plane. Fly with WASD or arrow keys, hold **Space** to climb, and hold **Shift** to descend. Land by the workbench and press **F** to park or re-equip it. The plane can cross the gaps between worlds; quest progress and plane ownership last for the current host session.
