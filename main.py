import asyncio
import json
import uuid
from enum import IntEnum
from datetime import datetime
from typing import Dict, List, Optional, Set
import redis
import psycopg2
from psycopg2.extras import RealDictCursor
from fastapi import FastAPI, WebSocket, WebSocketDisconnect, HTTPException, Depends
from pydantic import BaseModel
import numpy as np
from noise import snoise3
import os
from dotenv import load_dotenv

load_dotenv()

# Block Types Enum for clarity
class Block(IntEnum):
    AIR = 0
    GRASS = 1
    SAND = 2
    WATER = 3
    STONE = 4
    DIRT = 5
    SNOW = 6
    LOG = 7
    LEAVES = 8
    CACTUS = 9
    DEAD_BUSH = 10
    COAL_ORE = 11
    IRON_ORE = 12
    GOLD_ORE = 13
    DIAMOND_ORE = 14
    ROTTEN_FLESH = 15
    BONE = 16
    ARROW = 17
    STRING = 18
    STICK = 19
    TORCH = 20
    WOODEN_PICKAXE = 21
    WOODEN_SWORD = 22
    STONE_PICKAXE = 23
    FURNACE = 24
    IRON_INGOT = 25
    IRON_SWORD = 26
    IRON_HELMET = 27
    IRON_CHESTPLATE = 28
    IRON_LEGGINGS = 29
    IRON_BOOTS = 30
    IRON_PICKAXE = 31
    RAW_BEEF = 32
    COOKED_BEEF = 33
    WOODEN_HOE = 34
    WHEAT_SEEDS = 35
    WHEAT = 36
    FARMLAND = 37
    WHEAT_CROP = 38
    BREAD = 39

# Game Time Constants
GAME_TICK_DURATION_SECONDS = 1
DAY_DURATION_TICKS = 300  # 5 minutes
NIGHT_DURATION_TICKS = 300 # 5 minutes
FULL_CYCLE_TICKS = DAY_DURATION_TICKS + NIGHT_DURATION_TICKS

# Monster definitions
HOSTILE_MOBS = ["zombie", "skeleton", "spider"]
PASSIVE_MOBS = ["cow"]

MONSTER_STATS = {
    "zombie": {"health": 20, "damage": 5, "speed": 0.2},
    "skeleton": {"health": 15, "damage": 7, "speed": 0.25},
    "spider": {"health": 16, "damage": 6, "speed": 0.35},
    "cow": {"health": 10, "damage": 0, "speed": 0.25},
}

MONSTER_LOOT_TABLES = {
    "zombie": [
        # item_id, (min_quantity, max_quantity), chance_to_drop
        {"item_id": Block.ROTTEN_FLESH, "quantity": (0, 2), "chance": 0.8},
        {"item_id": Block.IRON_ORE, "quantity": (1, 1), "chance": 0.025} # Rare drop
    ],
    "skeleton": [
        {"item_id": Block.BONE, "quantity": (0, 2), "chance": 0.9},
        {"item_id": Block.ARROW, "quantity": (0, 2), "chance": 0.7}
    ],
    "spider": [
        {"item_id": Block.STRING, "quantity": (0, 2), "chance": 0.9}
    ],
    "cow": [
        {"item_id": Block.RAW_BEEF, "quantity": (1, 3), "chance": 1.0}
    ],
}

# Crafting Recipes
# The key is the string representation of the Block ID being crafted.
CRAFTING_RECIPES = {
    str(Block.STICK): {
        "produces": 4,
        "ingredients": {str(Block.LOG): 1}
    },
    str(Block.TORCH): {
        "produces": 4,
        "ingredients": {str(Block.COAL_ORE): 1, str(Block.STICK): 1}
    },
    str(Block.WOODEN_PICKAXE): {
        "produces": 1,
        "ingredients": {str(Block.STICK): 2, str(Block.LOG): 3}
    },
    str(Block.WOODEN_SWORD): {
        "produces": 1,
        "ingredients": {str(Block.STICK): 1, str(Block.LOG): 2}
    },
    str(Block.STONE_PICKAXE): {
        "produces": 1,
        "ingredients": {str(Block.STICK): 2, str(Block.STONE): 3}
    },
    str(Block.FURNACE): {
        "produces": 1,
        "ingredients": {str(Block.STONE): 8}
    },
    str(Block.IRON_SWORD): {
        "produces": 1,
        "ingredients": {str(Block.STICK): 1, str(Block.IRON_INGOT): 2}
    },
    str(Block.IRON_HELMET): {
        "produces": 1,
        "ingredients": {str(Block.IRON_INGOT): 5}
    },
    str(Block.IRON_CHESTPLATE): {
        "produces": 1,
        "ingredients": {str(Block.IRON_INGOT): 8}
    },
    str(Block.IRON_LEGGINGS): {
        "produces": 1,
        "ingredients": {str(Block.IRON_INGOT): 7}
    },
    str(Block.IRON_BOOTS): {
        "produces": 1,
        "ingredients": {str(Block.IRON_INGOT): 4}
    },
    str(Block.IRON_PICKAXE): {
        "produces": 1,
        "ingredients": {str(Block.STICK): 2, str(Block.IRON_INGOT): 3}
    },
    str(Block.WOODEN_HOE): {
        "produces": 1,
        "ingredients": {str(Block.STICK): 2, str(Block.LOG): 2}
    },
    str(Block.BREAD): {
        "produces": 1,
        "ingredients": {str(Block.WHEAT): 3}
    }
}

# Tool and Mining Definitions
TOOL_TIERS = {
    # Maps tool item IDs to their mining tier. Tier 0 is hand.
    str(Block.WOODEN_PICKAXE): 1,
    str(Block.STONE_PICKAXE): 2,
    str(Block.IRON_PICKAXE): 3,
}

BLOCK_MINING_PROPERTIES = {
    # Defines what tool tier is required to mine a block.
    # If a block is not in this dict, it can be broken by hand (tier 0) and drops itself.
    str(Block.STONE): {"required_tier": 1},
    str(Block.COAL_ORE): {"required_tier": 1},
    str(Block.IRON_ORE): {"required_tier": 2}, # Requires a stone pickaxe (to be added)
    str(Block.GOLD_ORE): {"required_tier": 3}, # Requires an iron pickaxe (to be added)
    str(Block.DIAMOND_ORE): {"required_tier": 3},
}

# Tool Durability
TOOL_DURABILITY = {
    str(Block.WOODEN_PICKAXE): 59,
    str(Block.STONE_PICKAXE): 131,
    str(Block.WOODEN_SWORD): 59,
    str(Block.IRON_SWORD): 250,
    str(Block.IRON_PICKAXE): 250,
    str(Block.IRON_HELMET): 165,
    str(Block.IRON_CHESTPLATE): 240,
    str(Block.IRON_LEGGINGS): 225,
    str(Block.IRON_BOOTS): 195,
}

# Repair Bonus
REPAIR_BONUS = 0.1 # 10% bonus durability when combining tools

# Smelting and Fuel Definitions
SMELTING_RECIPES = {
    # input_item_id: { "output": output_item_id, "time": ticks }
    str(Block.RAW_BEEF): {"output": Block.COOKED_BEEF, "time": 10},
    str(Block.IRON_ORE): {"output": Block.IRON_INGOT, "time": 10},
    str(Block.LOG): {"output": Block.COAL_ORE, "time": 10} # Making charcoal
}

FUEL_SOURCES = {
    # item_id: burn_time_in_ticks
    str(Block.COAL_ORE): 80, # Smelts 8 items
    str(Block.LOG): 15,      # Smelts 1.5 items
}

# Armor Protection
ARMOR_PROTECTION = {
    # Protection points (out of 20 in Minecraft)
    str(Block.IRON_HELMET): 2,
    str(Block.IRON_CHESTPLATE): 6,
    str(Block.IRON_LEGGINGS): 5,
    str(Block.IRON_BOOTS): 2,
}

# Food Properties
FOOD_PROPERTIES = {
    # item_id: {"hunger": hunger_points, "saturation": saturation_points}
    str(Block.ROTTEN_FLESH): {"hunger": 4, "saturation": 0.8},
    str(Block.RAW_BEEF): {"hunger": 3, "saturation": 1.8},
    str(Block.COOKED_BEEF): {"hunger": 8, "saturation": 12.8},
    str(Block.BREAD): {"hunger": 5, "saturation": 6},
}

# Weapon Damage
WEAPON_DAMAGE = {
    # Maps weapon item IDs to their damage value.
    str(Block.WOODEN_SWORD): 7,
    str(Block.IRON_SWORD): 9,
}
BARE_HAND_DAMAGE = 2

# Farming Properties
CROP_PROPERTIES = {
    str(Block.WHEAT_CROP): {
        "seed_item": Block.WHEAT_SEEDS,
        "max_stage": 7,
        "drops": {
            "item": Block.WHEAT,
            "quantity": (1, 1)
        },
        "seed_drops": {
            "item": Block.WHEAT_SEEDS,
            "quantity": (0, 2)
        }
    }
}

# A simple in-memory store for active monsters. For scalability, this could be moved to Redis.
# The key is the monster_id (str), and the value is the Monster object.
active_monsters: Dict[str, 'Monster'] = {}



# Models
class Player(BaseModel):
    id: str
    username: str
    x: float = 0.0
    y: float = 0.0
    z: float = 0.0
    health: int = 100
    hunger: int = 20
    saturation: float = 5.0
    inventory: Dict = {}
    equipment: Dict = {}
    realm_id: str = "default"

class WorldChunk(BaseModel):
    chunk_x: int
    chunk_z: int
    blocks: List[List[List[int]]]  # 3D array of block types (x, y, z)
    realm_id: str

class BuildAction(BaseModel):
    player_id: str
    x: int
    y: int
    z: int
    block_type: int
    action: str  # "place" or "break"

class ChatMessage(BaseModel):
    player_id: str
    message: str
    timestamp: datetime
    realm_id: str

class GameTime(BaseModel):
    tick: int
    phase: str
    full_cycle_ticks: int

class Monster(BaseModel):
    id: str
    monster_type: str  # e.g., "zombie", "skeleton"
    x: float
    y: float
    z: float
    health: int
    realm_id: str

class BlockEntity(BaseModel):
    x: int
    y: int
    z: int
    realm_id: str
    block_type: int
    state: Dict # e.g., {"input": {}, "fuel": {}, "output": {}, "burn_time": 0, "cook_time": 0}

class PlayerCreate(BaseModel):
    username: str
    realm_id: str = "default"
    character_data: Dict


# FastAPI App
app = FastAPI(title="MMORPG Backend", version="1.0.0")

# Redis connection for real-time state
redis_client = redis.Redis(
    host=os.getenv("REDIS_HOST", "localhost"),
    port=int(os.getenv("REDIS_PORT", 6379)),
    decode_responses=True
)

# PostgreSQL connection
def get_db_connection():
    return psycopg2.connect(
        host=os.getenv("DB_HOST", "localhost"),
        database=os.getenv("DB_NAME", "mmorpg"),
        user=os.getenv("DB_USER", "postgres"),
        password=os.getenv("DB_PASSWORD", "password"),
        cursor_factory=RealDictCursor
    )

# Connection Manager for WebSockets
class ConnectionManager:
    def __init__(self):
        self.active_connections: Dict[str, WebSocket] = {}
        self.player_realms: Dict[str, str] = {}

    async def connect(self, websocket: WebSocket, player_id: str, realm_id: str):
        await websocket.accept()
        self.active_connections[player_id] = websocket
        self.player_realms[player_id] = realm_id
        
        # Fetch character_data from DB to cache in Redis
        conn = get_db_connection()
        cursor = conn.cursor()
        cursor.execute("SELECT * FROM players WHERE id = %s", (player_id,))
        player_record = cursor.fetchone()
        cursor.close()
        conn.close()
        character_data_str = json.dumps(player_record.get('character_data', {})) if player_record else "{}"

        # Store player connection in Redis
        redis_client.hset(f"player:{player_id}", mapping={
            "connected": "true",
            "realm_id": realm_id,
            "last_seen": datetime.now().isoformat(),
            "character_data": character_data_str
        })
        # Initialize player state for fall damage
        redis_client.hset(f"player_state:{player_id}", mapping={
            "is_falling": "false",
            "fall_start_y": "0"
        })

        # Send the full initial state to the connecting player
        if player_record:
            await self.send_to_player(player_id, {
                "type": "initial_state",
                "health": player_record.get('health'),
                "hunger": player_record.get('hunger'),
                "saturation": player_record.get('saturation'),
                "inventory": player_record.get('inventory'),
                "equipment": player_record.get('equipment')
            })

    def disconnect(self, player_id: str):
        if player_id in self.active_connections:
            del self.active_connections[player_id]
        if player_id in self.player_realms:
            del self.player_realms[player_id]
        
        # Update Redis
        redis_client.hset(f"player:{player_id}", "connected", "false")

    async def send_to_player(self, player_id: str, message: dict):
        if player_id in self.active_connections:
            try:
                await self.active_connections[player_id].send_text(json.dumps(message))
            except Exception:
                self.disconnect(player_id)

    async def broadcast_to_realm(self, realm_id: str, message: dict, exclude_player: str = None):
        for player_id, websocket in self.active_connections.items():
            if (self.player_realms.get(player_id) == realm_id and 
                player_id != exclude_player):
                try:
                    await websocket.send_text(json.dumps(message))
                except Exception:
                    self.disconnect(player_id)

    async def broadcast_to_all(self, message: dict):
        # This is a simple implementation. For a very large number of players,
        # it might be better to use Redis Pub/Sub.
        for player_id, websocket in self.active_connections.items():
            try:
                await websocket.send_text(json.dumps(message))
            except Exception:
                self.disconnect(player_id)

manager = ConnectionManager()

# World Generation
class WorldGenerator:
    def __init__(self):
        self.chunk_size = 16
        self.max_height = 64
        self.sea_level = 28

        # Noise settings
        self.elevation_scale = 0.01
        self.biome_scale = 0.005      # Biomes are large scale features
        self.feature_scale = 0.05     # Features like trees are smaller scale
        self.cave_scale = 0.08        # Controls the size of cave systems
        self.cave_threshold = 0.6     # How open caves are. Higher value = smaller, rarer caves.

        # Ore generation settings
        self.ore_scale = 0.1  # General scale for ore veins
        self.coal_threshold = 0.7
        self.iron_threshold = 0.8
        self.gold_threshold = 0.9
        self.diamond_threshold = 0.95

        # Seed offsets for different noise maps
        self.elevation_seed = 0
        self.temperature_seed = 1
        self.moisture_seed = 2
        self.feature_seed = 3
        self.cave_seed = 4
        self.coal_seed = 5
        self.iron_seed = 6
        self.gold_seed = 7
        self.diamond_seed = 8

    def generate_chunk(self, chunk_x: int, chunk_z: int, realm_id: str) -> WorldChunk:
        """Generate a 16x64x16 chunk with 3D terrain and features."""
        # Initialize a 3D numpy array for the chunk (x, y, z)
        chunk_data = np.zeros((self.chunk_size, self.max_height, self.chunk_size), dtype=int)

        # Pass 1: Generate terrain height and base blocks
        height_map = np.zeros((self.chunk_size, self.chunk_size), dtype=int)
        biome_map = [[None for _ in range(self.chunk_size)] for _ in range(self.chunk_size)]

        for x_in_chunk in range(self.chunk_size):
            for z_in_chunk in range(self.chunk_size):
                world_x = chunk_x * self.chunk_size + x_in_chunk
                world_z = chunk_z * self.chunk_size + z_in_chunk

                # Get biome and height
                temp_noise = snoise3(world_x * self.biome_scale, world_z * self.biome_scale, self.temperature_seed)
                moisture_noise = snoise3(world_x * self.biome_scale, world_z * self.biome_scale, self.moisture_seed)
                biome = self.get_biome(temp_noise, moisture_noise)
                height = self.get_height(world_x, world_z, biome)

                height_map[x_in_chunk, z_in_chunk] = height
                biome_map[x_in_chunk][z_in_chunk] = biome

                # Fill column with blocks
                if height < self.sea_level:
                    # Water world
                    chunk_data[x_in_chunk, :height, z_in_chunk] = Block.SAND
                    chunk_data[x_in_chunk, height:self.sea_level, z_in_chunk] = Block.WATER
                else:
                    # Land world
                    surface_block = self.get_surface_block(height, biome)
                    chunk_data[x_in_chunk, 1:height-3, z_in_chunk] = Block.STONE
                    chunk_data[x_in_chunk, height-3:height, z_in_chunk] = Block.DIRT
                    chunk_data[x_in_chunk, height, z_in_chunk] = surface_block

        # Pass 1.5: Carve out caves using 3D Perlin noise
        for x_in_chunk in range(self.chunk_size):
            for z_in_chunk in range(self.chunk_size):
                world_x = chunk_x * self.chunk_size + x_in_chunk
                world_z = chunk_z * self.chunk_size + z_in_chunk
                
                # Iterate through the stone layer, below the surface
                for y in range(1, height_map[x_in_chunk, z_in_chunk]):
                    # Only carve out of stone blocks
                    if chunk_data[x_in_chunk, y, z_in_chunk] == Block.STONE:
                        # Get a 3D noise value. snoise3 is perfect for this.
                        cave_noise = (snoise3(
                            world_x * self.cave_scale,
                            y * self.cave_scale, # Using y-coordinate makes the noise 3D
                            world_z * self.cave_scale,
                            octaves=2, # More octaves = more detailed caves
                            base=self.cave_seed # Use a separate seed for caves
                        ) + 1) / 2 # Normalize noise from [-1, 1] to [0, 1]

                        if cave_noise > self.cave_threshold:
                            chunk_data[x_in_chunk, y, z_in_chunk] = Block.AIR

        # Pass 1.75: Generate ore veins
        for x_in_chunk in range(self.chunk_size):
            for z_in_chunk in range(self.chunk_size):
                world_x = chunk_x * self.chunk_size + x_in_chunk
                world_z = chunk_z * self.chunk_size + z_in_chunk
                
                # Iterate through the stone layer
                for y in range(1, height_map[x_in_chunk, z_in_chunk]):
                    # Only replace stone blocks
                    if chunk_data[x_in_chunk, y, z_in_chunk] == Block.STONE:
                        # Check for Diamond (rarest, deepest)
                        if y < 16:
                            diamond_noise = (snoise3(world_x * self.ore_scale, y * self.ore_scale, world_z * self.ore_scale, base=self.diamond_seed) + 1) / 2
                            if diamond_noise > self.diamond_threshold:
                                chunk_data[x_in_chunk, y, z_in_chunk] = Block.DIAMOND_ORE
                                continue # Ore placed, move to next block
                        
                        # Check for Gold (rare, deep)
                        if y < 32:
                            gold_noise = (snoise3(world_x * self.ore_scale, y * self.ore_scale, world_z * self.ore_scale, base=self.gold_seed) + 1) / 2
                            if gold_noise > self.gold_threshold:
                                chunk_data[x_in_chunk, y, z_in_chunk] = Block.GOLD_ORE
                                continue

                        # Check for Iron (common, mid-level)
                        if y < 50:
                            iron_noise = (snoise3(world_x * self.ore_scale, y * self.ore_scale, world_z * self.ore_scale, base=self.iron_seed) + 1) / 2
                            if iron_noise > self.iron_threshold:
                                chunk_data[x_in_chunk, y, z_in_chunk] = Block.IRON_ORE
                                continue

                        # Check for Coal (most common, any level, larger veins)
                        coal_noise = (snoise3(world_x * self.ore_scale * 0.8, y * self.ore_scale * 0.8, world_z * self.ore_scale * 0.8, base=self.coal_seed) + 1) / 2
                        if coal_noise > self.coal_threshold:
                            chunk_data[x_in_chunk, y, z_in_chunk] = Block.COAL_ORE
                            continue

        # Pass 2: Add decorations and features
        for x_in_chunk in range(self.chunk_size):
            for z_in_chunk in range(self.chunk_size):
                world_x = chunk_x * self.chunk_size + x_in_chunk
                world_z = chunk_z * self.chunk_size + z_in_chunk

                height = height_map[x_in_chunk, z_in_chunk]
                biome = biome_map[x_in_chunk][z_in_chunk]
                
                # Only place features on land above sea level
                if height >= self.sea_level:
                    feature_noise = (snoise3(world_x * self.feature_scale, world_z * self.feature_scale, self.feature_seed) + 1) / 2

                    # Place trees in forests if the ground is grass
                    if biome in ["forest", "snowy_forest", "jungle"] and chunk_data[x_in_chunk, height, z_in_chunk] == Block.GRASS:
                        if feature_noise > 0.9:  # Use noise to create clumps of trees
                            self.place_tree(chunk_data, x_in_chunk, height + 1, z_in_chunk)
                    
                    # Place cacti in deserts if the ground is sand
                    elif biome == "desert" and chunk_data[x_in_chunk, height, z_in_chunk] == Block.SAND:
                        if feature_noise > 0.95:
                            self.place_cactus(chunk_data, x_in_chunk, height + 1, z_in_chunk)

        return WorldChunk(
            chunk_x=chunk_x,
            chunk_z=chunk_z,
            blocks=chunk_data.tolist(),  # Convert numpy array to list for JSON
            realm_id=realm_id
        )

    def place_tree(self, chunk_data, x, y, z):
        """Places a simple tree structure into the chunk data."""
        tree_height = np.random.randint(4, 7)
        canopy_size = 2

        # Check if tree fits vertically
        if y + tree_height + canopy_size >= self.max_height:
            return

        # Place trunk
        for i in range(tree_height):
            if y + i < self.max_height:
                chunk_data[x, y + i, z] = Block.LOG

        # Place leaves (canopy)
        canopy_y_start = y + tree_height - 2
        for ly in range(-canopy_size, canopy_size + 1):
            for lx in range(-canopy_size, canopy_size + 1):
                for lz in range(-canopy_size, canopy_size + 1):
                    # Skip corners for a more rounded shape
                    if abs(lx) == canopy_size and abs(lz) == canopy_size and abs(ly) > 0:
                        continue
                    
                    # Check chunk boundaries
                    if (0 <= x + lx < self.chunk_size and
                        0 <= z + lz < self.chunk_size and
                        canopy_y_start + ly < self.max_height):
                        
                        # Only replace air blocks
                        if chunk_data[x + lx, canopy_y_start + ly, z + lz] == Block.AIR:
                            chunk_data[x + lx, canopy_y_start + ly, z + lz] = Block.LEAVES

    def place_cactus(self, chunk_data, x, y, z):
        """Places a cactus."""
        cactus_height = np.random.randint(2, 4)
        if y + cactus_height >= self.max_height:
            return
        
        for i in range(cactus_height):
            chunk_data[x, y + i, z] = Block.CACTUS

    def get_biome(self, temp_noise: float, moisture_noise: float) -> str:
        if temp_noise < -0.3:  # Cold
            if moisture_noise > 0.2:
                return "snowy_forest"
            else:
                return "tundra"
        elif temp_noise < 0.4:  # Temperate
            if moisture_noise > 0.3:
                return "forest"
            elif moisture_noise < -0.3:
                return "plains"
            else:
                return "grassland"
        else:  # Hot
            if moisture_noise > 0.0:
                return "jungle"
            else:
                return "desert"

    def get_height(self, world_x: int, world_z: int, biome: str) -> int:
        # Base elevation noise
        base_height_noise = snoise3(world_x * self.elevation_scale, world_z * self.elevation_scale, self.elevation_seed)
        
        # Normalize to 0-1 range
        normalized_height = (base_height_noise + 1) / 2
        
        # Biome-specific height modifications
        if biome in ["jungle", "snowy_forest"]:
            # Hilly / Mountainous biomes
            height = self.sea_level + normalized_height * 50
        elif biome == "desert":
            # Deserts are flatter
            height = self.sea_level + normalized_height * 15
        else:  # Default for plains, grassland, tundra
            height = self.sea_level + normalized_height * 30

        return max(1, min(int(height), self.max_height - 1))

    def get_surface_block(self, height: int, biome: str) -> int:
        if height < self.sea_level:
            return Block.WATER

        if biome == "desert":
            return Block.SAND
        elif biome == "tundra":
            return Block.SNOW if height > self.sea_level + 5 else Block.DIRT
        elif biome == "snowy_forest":
            return Block.SNOW
        
        # For most other biomes, it's grass above sea level
        if height > self.sea_level:
            return Block.GRASS
        
        # Fallback for shorelines
        if height == self.sea_level:
            return Block.SAND

        return Block.DIRT  # Fallback

world_gen = WorldGenerator()

# --- Monster Management ---

async def monster_spawner():
    """Background task to spawn monsters at night near players."""
    SPAWN_RADIUS_MIN = 15
    SPAWN_RADIUS_MAX = 30
    MAX_MONSTERS_PER_REALM = 50

    while True:
        await asyncio.sleep(10) # Try to spawn every 10 seconds

        game_phase = redis_client.get("game_time:day_phase")
        
        mobs_to_spawn_this_cycle = []
        if game_phase == "night":
            mobs_to_spawn_this_cycle = HOSTILE_MOBS
        else: # day
            mobs_to_spawn_this_cycle = PASSIVE_MOBS

        if not mobs_to_spawn_this_cycle: continue

        online_players = list(manager.active_connections.keys())
        if not online_players:
            continue

        realm_id = "default" # Assuming one realm for now
        if len(active_monsters) >= MAX_MONSTERS_PER_REALM:
            continue

        # Pick a random player to spawn near
        player_id = np.random.choice(online_players)
        player_pos_data = redis_client.hgetall(f"player_pos:{player_id}")
        if not player_pos_data:
            continue

        player_x, player_z = float(player_pos_data['x']), float(player_pos_data['z'])

        # Try to find a valid spawn location
        for _ in range(10): # 10 attempts to find a spot
            angle = np.random.uniform(0, 2 * np.pi)
            radius = np.random.uniform(SPAWN_RADIUS_MIN, SPAWN_RADIUS_MAX)
            spawn_x = int(player_x + radius * np.cos(angle))
            spawn_z = int(player_z + radius * np.sin(angle))

            # Find ground level by scanning down from the sky
            spawn_y = -1
            for y_scan in range(world_gen.max_height - 1, 0, -1):
                block = await get_block_at(realm_id, spawn_x, y_scan, spawn_z)
                if block != Block.AIR and block != Block.WATER and block != Block.LEAVES:
                    spawn_y = y_scan + 1 # Spawn on top of this block
                    break
            
            if spawn_y == -1: continue # No suitable ground found

            # Check if the space is clear for spawning (2 blocks high)
            block_at_spawn = await get_block_at(realm_id, spawn_x, spawn_y, spawn_z)
            block_one_above = await get_block_at(realm_id, spawn_x, spawn_y + 1, spawn_z)

            if block_at_spawn == Block.AIR and block_one_above == Block.AIR:
                # Valid spawn point found!
                monster_type = np.random.choice(mobs_to_spawn_this_cycle)
                monster_id = str(uuid.uuid4())
                monster_stats = MONSTER_STATS[monster_type]
                
                new_monster = Monster(
                    id=monster_id,
                    monster_type=monster_type,
                    x=spawn_x + 0.5, y=spawn_y, z=spawn_z + 0.5,
                    health=monster_stats["health"],
                    realm_id=realm_id
                )
                active_monsters[monster_id] = new_monster
                
                await manager.broadcast_to_realm(realm_id, {
                    "type": "monster_spawned",
                    "monster": new_monster.dict()
                })
                break # Stop trying to spawn for this player this cycle

async def monster_ai_ticker():
    """Background task for monster AI, movement, and attacks."""
    ATTACK_RANGE_SQ = 2.0**2
    AGGRO_RANGE_SQ = 16.0**2

    while True:
        await asyncio.sleep(1) # AI tick every second

        if not active_monsters: continue
        
        online_players = {pid: redis_client.hgetall(f"player_pos:{pid}") for pid in manager.active_connections.keys()}

        for monster_id, monster in list(active_monsters.items()):
            nearest_player_id, min_dist_sq = find_nearest_player(monster, online_players)
            
            if monster.monster_type in HOSTILE_MOBS:
                if nearest_player_id and min_dist_sq < AGGRO_RANGE_SQ:
                    # Player is in aggro range
                    if min_dist_sq < ATTACK_RANGE_SQ:
                        # Attack player
                        await attack_player(monster, nearest_player_id)
                    else:
                        # Move towards player
                        await move_monster_towards_player(monster, online_players[nearest_player_id])
                else:
                    # Wander randomly (or stand still for this simple version)
                    pass

# --- Game Time Ticker ---

async def game_time_ticker():
    """A background task that advances the game time."""
    while True:
        await asyncio.sleep(GAME_TICK_DURATION_SECONDS)
        
        try:
            # Increment tick and wrap around the cycle
            current_tick = int(redis_client.incr("game_time:tick"))
            current_tick %= FULL_CYCLE_TICKS
            redis_client.set("game_time:tick", current_tick)

            # Determine current phase
            old_phase = redis_client.get("game_time:day_phase")
            new_phase = "day" if current_tick < DAY_DURATION_TICKS else "night"
            
            if new_phase != old_phase:
                redis_client.set("game_time:day_phase", new_phase)
                # Broadcast change to all players
                await manager.broadcast_to_all({"type": "time_update", "phase": new_phase, "tick": current_tick})
        except Exception as e:
            # Log error but don't crash the ticker
            print(f"Error in game time ticker: {e}")

async def player_stats_ticker():
    """Background task to manage player hunger, saturation, and health regen."""
    while True:
        await asyncio.sleep(4) # Ticks every 4 seconds for health/hunger effects
        
        online_players = list(manager.active_connections.keys())
        if not online_players:
            continue

        # Process each player in their own transaction for robustness
        for player_id in online_players:
            conn = get_db_connection()
            cursor = conn.cursor()
            try:
                cursor.execute("SELECT health, hunger, saturation, realm_id FROM players WHERE id = %s FOR UPDATE", (player_id,))
                player_stats = cursor.fetchone()
                if not player_stats: continue

                health, hunger, saturation, realm_id = player_stats['health'], player_stats['hunger'], player_stats['saturation'], player_stats['realm_id']
                original_health = health
                
                # --- Health Regeneration ---
                if health < 100 and hunger >= 18:
                    health = min(100, health + 1)
                    # Healing costs saturation/hunger
                    if saturation > 0:
                        saturation = max(0, saturation - 1.0)
                    else:
                        hunger = max(0, hunger - 1)
                
                # --- Starvation Damage ---
                elif hunger <= 0 and health > 0: # Only apply damage if alive
                    health = max(0, health - 1)

                # --- Passive Hunger/Saturation Depletion ---
                # A more advanced system would tie this to player actions (running, jumping).
                if saturation > 0:
                    saturation = max(0, saturation - 0.1)
                else:
                    hunger = max(0, hunger - 0.1)
                
                cursor.execute(
                    "UPDATE players SET health = %s, hunger = %s, saturation = %s WHERE id = %s",
                    (health, int(hunger), saturation, player_id)
                )
                conn.commit()
                
                await manager.send_to_player(player_id, {
                    "type": "player_stats_update",
                    "health": health, "hunger": int(hunger), "saturation": saturation
                })

                # --- Handle Death ---
                if original_health > 0 and health <= 0:
                    await manager.broadcast_to_realm(realm_id, {"type": "player_died", "player_id": player_id})
                    respawn_data = await respawn_player(player_id, realm_id)
                    await manager.send_to_player(player_id, {"type": "player_respawn", "data": respawn_data})

            except Exception as e:
                print(f"Error in player stats ticker for player {player_id}: {e}")
                conn.rollback()
            finally:
                cursor.close()
                conn.close()

# --- Furnace Ticker ---

async def furnace_ticker():
    """A background task that processes active furnaces."""
    while True:
        await asyncio.sleep(GAME_TICK_DURATION_SECONDS)
        conn = get_db_connection()
        cursor = conn.cursor()
        try:
            cursor.execute("SELECT * FROM block_entities WHERE block_type = %s FOR UPDATE", (Block.FURNACE,))
            active_furnaces = cursor.fetchall()
            
            for furnace_record in active_furnaces:
                state = furnace_record['state']
                is_state_changed = False

                is_burning = state.get('burn_time', 0) > 0
                
                # Handle fuel consumption to start burning
                if not is_burning and state.get('input') and state.get('fuel'):
                    fuel_item_id = str(state['fuel']['item_id'])
                    if fuel_item_id in FUEL_SOURCES:
                        state['fuel']['quantity'] -= 1
                        if state['fuel']['quantity'] <= 0:
                            state.pop('fuel')
                        
                        state['burn_time'] = FUEL_SOURCES[fuel_item_id]
                        is_burning = True
                        is_state_changed = True

                # Handle smelting process
                if is_burning:
                    input_item_id = str(state.get('input', {}).get('item_id'))
                    recipe = SMELTING_RECIPES.get(input_item_id)
                    
                    if recipe:
                        output_item_id = recipe['output']
                        output_slot = state.get('output')
                        
                        # Check if output is clear or can be stacked
                        if not output_slot or (output_slot['item_id'] == output_item_id and output_slot['quantity'] < 64):
                            state['cook_time'] = state.get('cook_time', 0) + 1
                            is_state_changed = True

                            if state['cook_time'] >= recipe['time']:
                                # Smelting complete: consume input, produce output
                                state['input']['quantity'] -= 1
                                if state['input']['quantity'] <= 0:
                                    state.pop('input')
                                
                                if not output_slot:
                                    state['output'] = {'item_id': output_item_id, 'quantity': 1}
                                else:
                                    state['output']['quantity'] += 1
                                
                                state['cook_time'] = 0
                        else: # Output blocked
                            state['cook_time'] = 0
                    else: # No valid recipe for input
                        state['cook_time'] = 0

                    state['burn_time'] -= 1
                    is_state_changed = True

                if is_state_changed:
                    cursor.execute(
                        "UPDATE block_entities SET state = %s WHERE x = %s AND y = %s AND z = %s AND realm_id = %s",
                        (json.dumps(state), furnace_record['x'], furnace_record['y'], furnace_record['z'], furnace_record['realm_id'])
                    )
            conn.commit()
        except Exception as e:
            print(f"Error in furnace ticker: {e}")
            conn.rollback()
        finally:
            cursor.close()
            conn.close()

async def farming_ticker():
    """A background task for crop growth and farmland hydration."""
    while True:
        await asyncio.sleep(20) # Ticks every 20 seconds
        conn = get_db_connection()
        cursor = conn.cursor()
        try:
            # Get all farmland and crop entities
            cursor.execute("SELECT x, y, z, block_type, state FROM block_entities WHERE block_type IN (%s, %s)", (Block.FARMLAND, Block.WHEAT_CROP))
            entities = cursor.fetchall()
            if not entities: continue

            farmland_coords = {(e['x'], e['y'], e['z']) for e in entities if e['block_type'] == Block.FARMLAND}
            hydrated_farmland = set()

            # Pass 1: Check hydration for all farmland
            for x, y, z in farmland_coords:
                is_hydrated = False
                for check_x in range(x - 4, x + 5):
                    for check_z in range(z - 4, z + 5):
                        if (check_x, y, check_z) == (x, y, z): continue
                        block_type = await get_block_at("default", check_x, y, check_z)
                        if block_type == Block.WATER:
                            is_hydrated = True
                            hydrated_farmland.add((x, y, z))
                            break
                    if is_hydrated: break
            
            # Pass 2: Grow crops
            for entity in entities:
                if entity['block_type'] == Block.WHEAT_CROP:
                    state = entity['state']
                    current_stage = state.get('stage', 0)
                    max_stage = CROP_PROPERTIES[str(Block.WHEAT_CROP)]['max_stage']

                    if current_stage < max_stage:
                        # Check if on hydrated soil
                        is_on_hydrated = (entity['x'], entity['y'] - 1, entity['z']) in hydrated_farmland
                        growth_chance = 0.5 if is_on_hydrated else 0.2

                        if np.random.rand() < growth_chance:
                            state['stage'] = current_stage + 1
                            cursor.execute(
                                "UPDATE block_entities SET state = %s WHERE x=%s AND y=%s AND z=%s AND realm_id=%s",
                                (json.dumps(state), entity['x'], entity['y'], entity['z'], "default")
                            )
                            await manager.broadcast_to_realm("default", {"type": "block_entity_state", "x": entity['x'], "y": entity['y'], "z": entity['z'], "state": state})
            conn.commit()
        except Exception as e:
            print(f"Error in farming ticker: {e}")
            conn.rollback()
        finally:
            cursor.close()
            conn.close()

# --- Monster AI Helpers ---

def find_nearest_player(monster: Monster, online_players: Dict) -> (Optional[str], float):
    """Finds the nearest player to a monster."""
    nearest_player_id = None
    min_dist_sq = float('inf')
    
    for pid, ppos in online_players.items():
        if not ppos: continue
        dist_sq = (monster.x - float(ppos['x']))**2 + (monster.z - float(ppos['z']))**2
        if dist_sq < min_dist_sq:
            min_dist_sq = dist_sq
            nearest_player_id = pid
    return nearest_player_id, min_dist_sq

async def attack_player(monster: Monster, player_id: str):
    """Makes a monster attack a player."""
    raw_damage = MONSTER_STATS[monster.monster_type]["damage"]
    await apply_damage_to_player(player_id, raw_damage, source_monster_id=monster.id)
    # In a real game, add an attack cooldown for the monster.

async def apply_damage_to_player(player_id: str, raw_damage: int, source_monster_id: Optional[str] = None):
    """
    Applies damage to a player, calculating armor reduction and durability loss.
    This is the central function for all player damage.
    """
    if raw_damage <= 0:
        return

    conn = get_db_connection()
    cursor = conn.cursor()
    try:
        cursor.execute("SELECT health, equipment, inventory FROM players WHERE id = %s FOR UPDATE", (player_id,))
        player_record = cursor.fetchone()
        if not player_record: return

        equipment = player_record['equipment']
        inventory = player_record['inventory']
        
        # Calculate total protection from equipped armor
        total_protection = 0
        equipped_armor_keys = []
        for slot, item_key in equipment.items():
            if item_key in inventory and "item_id" in inventory[item_key]:
                item_id_str = str(inventory[item_key]['item_id'])
                total_protection += ARMOR_PROTECTION.get(item_id_str, 0)
                equipped_armor_keys.append(item_key)

        # Reduce damage (each protection point reduces damage by 4%, up to 80%)
        damage_reduction = min(total_protection * 0.04, 0.8)
        final_damage = max(1, int(raw_damage * (1 - damage_reduction)))

        # Apply durability loss to armor
        if equipped_armor_keys:
            durability_damage = max(1, int(raw_damage / 4))
            for item_key in equipped_armor_keys:
                inventory[item_key]['durability'] -= durability_damage
                if inventory[item_key]['durability'] <= 0:
                    del inventory[item_key]
                    for slot, key in list(equipment.items()):
                        if key == item_key: del equipment[slot]
        
        new_health = max(0, player_record['health'] - final_damage)
        cursor.execute("UPDATE players SET health = %s, inventory = %s, equipment = %s WHERE id = %s", (new_health, json.dumps(inventory), json.dumps(equipment), player_id))
        conn.commit()
        
        # Broadcast the health update to the realm
        await manager.broadcast_to_realm(player_record['realm_id'], {
            "type": "entity_health_update",
            "entity_id": player_id,
            "entity_type": "player",
            "current_health": new_health,
            "max_health": 100 # Assuming max health is 100
        })

        await manager.send_to_player(player_id, {"type": "inventory_update", "inventory": inventory})
        await manager.send_to_player(player_id, {"type": "equipment_update", "equipment": equipment})

        # Handle death after broadcasting health update
        if new_health <= 0:
            await manager.broadcast_to_realm("default", {"type": "player_died", "player_id": player_id})
            respawn_data = await respawn_player(player_id, "default")
            await manager.send_to_player(player_id, {"type": "player_respawn", "data": respawn_data})
    finally:
        cursor.close()
        conn.close()

async def move_monster_towards_player(monster: Monster, player_pos: Dict):
    """Moves a monster one step towards a player."""
    player_x, player_z = float(player_pos['x']), float(player_pos['z'])
    
    direction_x = player_x - monster.x
    direction_z = player_z - monster.z
    dist = np.sqrt(direction_x**2 + direction_z**2)
    
    if dist == 0: return

    speed = MONSTER_STATS[monster.monster_type]["speed"]
    monster.x += (direction_x / dist) * speed
    monster.z += (direction_z / dist) * speed
    
    await manager.broadcast_to_realm(monster.realm_id, {
        "type": "monster_moved",
        "monster_id": monster.id,
        "x": monster.x, "y": monster.y, "z": monster.z
    })

# --- Database & World Interaction Helpers ---

async def update_block_in_world(realm_id: str, x: int, y: int, z: int, new_block_type: int) -> Optional[int]:
    """
    Updates a single block in the world, saves it to the database, and returns the old block type.
    This is a core function for any world modification.
    """
    chunk_x = x // world_gen.chunk_size
    chunk_z = z // world_gen.chunk_size
    x_in_chunk = x % world_gen.chunk_size
    z_in_chunk = z % world_gen.chunk_size
    y_coord = y

    if not (0 <= y_coord < world_gen.max_height):
        return None  # Out of bounds vertically

    conn = get_db_connection()
    cursor = conn.cursor()
    try:
        # Lock the chunk row to prevent race conditions on the same chunk
        cursor.execute(
            "SELECT blocks FROM world_chunks WHERE chunk_x = %s AND chunk_z = %s AND realm_id = %s FOR UPDATE",
            (chunk_x, chunk_z, realm_id)
        )
        chunk_record = cursor.fetchone()
        if not chunk_record:
            return None  # Chunk doesn't exist, can't modify it

        blocks = json.loads(chunk_record['blocks'])
        
        # Get the old block type and update to the new one
        old_block_type = blocks[x_in_chunk][y_coord][z_in_chunk]
        
        if old_block_type == new_block_type:
            return None  # No change needed

        blocks[x_in_chunk][y_coord][z_in_chunk] = new_block_type

        # Save the modified chunk back to the database
        cursor.execute(
            "UPDATE world_chunks SET blocks = %s WHERE chunk_x = %s AND chunk_z = %s AND realm_id = %s",
            (json.dumps(blocks), chunk_x, chunk_z, realm_id)
        )
        conn.commit()

        # Invalidate Redis cache for this chunk
        redis_client.delete(f"chunk:{realm_id}:{chunk_x}:{chunk_z}")
        
        return old_block_type
    finally:
        cursor.close()
        conn.close()

async def add_item_to_player_inventory(player_id: str, item_id: int, quantity: int, cursor) -> Dict:
    """
    Adds a quantity of a STACKABLE item to a player's inventory.
    NOTE: This function is designed to be called within an existing DB transaction.
    """
    cursor.execute("SELECT inventory FROM players WHERE id = %s FOR UPDATE", (player_id,))
    player_record = cursor.fetchone()
    if not player_record:
        raise Exception(f"Player with ID {player_id} not found for inventory update.")

    inventory = player_record['inventory']
    item_key = str(item_id)

    if item_key not in inventory:
        inventory[item_key] = {"quantity": 0}
    
    inventory[item_key]["quantity"] = inventory[item_key].get("quantity", 0) + quantity
    
    cursor.execute("UPDATE players SET inventory = %s WHERE id = %s", (json.dumps(inventory), player_id))
    return inventory

async def remove_item_from_player_inventory(player_id: str, item_id: int, quantity: int, cursor) -> Optional[Dict]:
    """
    Removes a quantity of a STACKABLE item from a player's inventory.
    Returns the updated inventory on success, None on failure.
    NOTE: This function is designed to be called within an existing DB transaction.
    """
    cursor.execute("SELECT inventory FROM players WHERE id = %s FOR UPDATE", (player_id,))
    player_record = cursor.fetchone()
    if not player_record:
        return None

    inventory = player_record['inventory']
    item_key = str(item_id)

    if item_key not in inventory or inventory[item_key].get("quantity", 0) < quantity:
        return None # Not enough items

    inventory[item_key]["quantity"] -= quantity
    if inventory[item_key]["quantity"] <= 0:
        del inventory[item_key]

    cursor.execute("UPDATE players SET inventory = %s WHERE id = %s", (json.dumps(inventory), player_id))
    return inventory

async def process_crafting(player_id: str, item_id_to_craft: str) -> Optional[Dict]:
    """
    Processes a crafting request atomically. Checks ingredients, removes them, and adds the crafted item.
    Returns the updated inventory on success, None on failure.
    """
    recipe = CRAFTING_RECIPES.get(item_id_to_craft)
    if not recipe:
        return None  # Recipe not found

    conn = get_db_connection()
    cursor = conn.cursor()
    try:
        # Lock the player row to ensure an atomic inventory update
        cursor.execute("SELECT inventory FROM players WHERE id = %s FOR UPDATE", (player_id,))
        player_record = cursor.fetchone()
        if not player_record:
            return None

        inventory = player_record['inventory']
        ingredients = recipe["ingredients"]

        # 1. Check if all ingredients are available
        for ingredient_id, required_qty in ingredients.items():
            if ingredient_id not in inventory or inventory[ingredient_id].get("quantity", 0) < required_qty:
                conn.rollback()
                return None  # Not enough ingredients

        # 2. All ingredients are present, so remove them
        for ingredient_id, required_qty in ingredients.items():
            inventory[ingredient_id]["quantity"] -= required_qty
            if inventory[ingredient_id]["quantity"] == 0:
                del inventory[ingredient_id]

        # 3. Add the crafted item(s)
        produced_item_id_str = item_id_to_craft
        produced_qty = recipe["produces"]

        if produced_item_id_str in TOOL_DURABILITY:
            # It's a unique item with durability. Add one for each quantity produced.
            for _ in range(produced_qty):
                instance_id = str(uuid.uuid4())
                inventory[instance_id] = {
                    "item_id": int(produced_item_id_str),
                    "durability": TOOL_DURABILITY[produced_item_id_str]
                }
        else:
            # It's a stackable item
            if produced_item_id_str not in inventory:
                inventory[produced_item_id_str] = {"quantity": 0}
            inventory[produced_item_id_str]["quantity"] += produced_qty

        # 4. Save the single, updated inventory object back to the database
        cursor.execute("UPDATE players SET inventory = %s WHERE id = %s", (json.dumps(inventory), player_id))
        conn.commit()
        return inventory
    finally:
        cursor.close()
        conn.close()

async def get_block_at(realm_id: str, x: int, y: int, z: int) -> Optional[int]:
    """Retrieves the block type at a specific world coordinate, using cache."""
    if not (0 <= y < world_gen.max_height):
        return Block.AIR # Treat out of bounds as air

    chunk_x = x // world_gen.chunk_size
    chunk_z = z // world_gen.chunk_size
    x_in_chunk = x % world_gen.chunk_size
    z_in_chunk = z % world_gen.chunk_size

    # Check Redis cache first for the chunk's blocks
    cached_chunk_blocks = redis_client.get(f"chunk:{realm_id}:{chunk_x}:{chunk_z}")
    if cached_chunk_blocks:
        blocks = json.loads(cached_chunk_blocks)
        return blocks[x_in_chunk][y][z_in_chunk]

    # If not in cache, get from DB
    conn = get_db_connection()
    cursor = conn.cursor()
    try:
        cursor.execute(
            "SELECT blocks FROM world_chunks WHERE chunk_x = %s AND chunk_z = %s AND realm_id = %s",
            (chunk_x, chunk_z, realm_id)
        )
        chunk_record = cursor.fetchone()
        if chunk_record:
            blocks_json = chunk_record['blocks']
            blocks = json.loads(blocks_json)
            # Cache it for future requests
            redis_client.setex(f"chunk:{realm_id}:{chunk_x}:{chunk_z}", 3600, blocks_json) # Cache for 1 hour
            return blocks[x_in_chunk][y][z_in_chunk]
        else:
            # If chunk doesn't exist in DB, it's not generated yet. Treat as air.
            return Block.AIR
    finally:
        cursor.close()
        conn.close()

async def update_player_health(player_id: str, health_change: int) -> Optional[int]:
    """
    Updates a player's health by a certain amount (positive for healing, negative for damage).
    Returns the new health value, or None if player not found.
    """
    conn = get_db_connection()
    cursor = conn.cursor()
    try:
        cursor.execute("SELECT health FROM players WHERE id = %s FOR UPDATE", (player_id,))
        player_record = cursor.fetchone()
        if not player_record:
            return None

        current_health = player_record['health']
        new_health = max(0, current_health + health_change) # Health can't be negative

        if new_health != current_health:
            cursor.execute("UPDATE players SET health = %s WHERE id = %s", (new_health, player_id))
            conn.commit()
        
        return new_health
    finally:
        cursor.close()
        conn.close()

async def respawn_player(player_id: str, realm_id: str) -> Optional[Dict]:
    """Resets a player's health and moves them to the default spawn point."""
    conn = get_db_connection()
    cursor = conn.cursor()
    try:
        # Spawn point is hardcoded at a safe height above the center of the world.
        spawn_x, spawn_y, spawn_z = 0.5, 65.0, 0.5
        default_health = 100

        cursor.execute(
            "UPDATE players SET health = %s, x = %s, y = %s, z = %s WHERE id = %s RETURNING health, x, y, z",
            (default_health, spawn_x, spawn_y, spawn_z, player_id)
        )
        respawn_data = cursor.fetchone()
        conn.commit()
        
        if respawn_data:
            return dict(respawn_data)
        return None
    finally:
        cursor.close()
        conn.close()

# Database initialization
def init_database():
    """Initialize PostgreSQL tables"""
    conn = get_db_connection()
    cursor = conn.cursor()
    
    # Players table
    cursor.execute("""
        CREATE TABLE IF NOT EXISTS players (
            id VARCHAR(36) PRIMARY KEY,
            username VARCHAR(50) UNIQUE NOT NULL,
            x FLOAT DEFAULT 0,
            y FLOAT DEFAULT 0,
            z FLOAT DEFAULT 0,
            health INTEGER DEFAULT 100,
            inventory JSONB DEFAULT '{}',
            realm_id VARCHAR(36) DEFAULT 'default',
            created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
            last_login TIMESTAMP DEFAULT CURRENT_TIMESTAMP
        )
    """)
    # Add equipment column if it doesn't exist
    cursor.execute("""
        DO $$
        BEGIN
            IF NOT EXISTS (SELECT 1 FROM information_schema.columns WHERE table_name='players' AND column_name='equipment') THEN
                ALTER TABLE players ADD COLUMN equipment JSONB DEFAULT '{}';
            END IF;
            IF NOT EXISTS (SELECT 1 FROM information_schema.columns WHERE table_name='players' AND column_name='hunger') THEN
                ALTER TABLE players ADD COLUMN hunger INTEGER DEFAULT 20;
            END IF;
            IF NOT EXISTS (SELECT 1 FROM information_schema.columns WHERE table_name='players' AND column_name='saturation') THEN
                ALTER TABLE players ADD COLUMN saturation FLOAT DEFAULT 5.0;
            END IF;
            IF NOT EXISTS (SELECT 1 FROM information_schema.columns WHERE table_name='players' AND column_name='character_data') THEN
                ALTER TABLE players ADD COLUMN character_data JSONB DEFAULT '{}';
            END IF;
        END $$;
    """)
    
    # World chunks table
    cursor.execute("""
        CREATE TABLE IF NOT EXISTS world_chunks (
            id SERIAL PRIMARY KEY,
            chunk_x INTEGER NOT NULL,
            chunk_z INTEGER NOT NULL,
            realm_id VARCHAR(36) NOT NULL,
            blocks JSONB NOT NULL,
            created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
            UNIQUE(chunk_x, chunk_z, realm_id)
        )
    """)
    
    # Block entities table (for furnaces, chests, etc.)
    cursor.execute("""
        CREATE TABLE IF NOT EXISTS block_entities (
            x INTEGER NOT NULL,
            y INTEGER NOT NULL,
            z INTEGER NOT NULL,
            realm_id VARCHAR(36) NOT NULL,
            block_type INTEGER NOT NULL,
            state JSONB DEFAULT '{}',
            PRIMARY KEY (x, y, z, realm_id)
        )
    """)
    
    # Monsters table
    cursor.execute("""
        CREATE TABLE IF NOT EXISTS monsters (
            id VARCHAR(36) PRIMARY KEY,
            monster_type VARCHAR(50) NOT NULL,
            x FLOAT NOT NULL,
            y FLOAT NOT NULL,
            z FLOAT NOT NULL,
            health INTEGER NOT NULL,
            realm_id VARCHAR(36) NOT NULL,
            created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
        )
    """)
    
    # Build actions log
    cursor.execute("""
        CREATE TABLE IF NOT EXISTS build_actions (
            id SERIAL PRIMARY KEY,
            player_id VARCHAR(36) NOT NULL,
            x INTEGER NOT NULL,
            y INTEGER NOT NULL,
            z INTEGER NOT NULL,
            block_type INTEGER NOT NULL,
            action VARCHAR(10) NOT NULL,
            realm_id VARCHAR(36) NOT NULL,
            created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
        )
    """)
    
    # Chat messages
    cursor.execute("""
        CREATE TABLE IF NOT EXISTS chat_messages (
            id SERIAL PRIMARY KEY,
            player_id VARCHAR(36) NOT NULL,
            message TEXT NOT NULL,
            realm_id VARCHAR(36) NOT NULL,
            created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
        )
    """)
    
    conn.commit()
    cursor.close()
    conn.close()

# API Routes
@app.get("/api/game/definitions")
async def get_game_definitions():
    """Returns static game definitions like recipes and item properties."""
    return {
        "blocks": {member.name: member.value for member in Block},
        "crafting_recipes": CRAFTING_RECIPES,
        "tool_durability": TOOL_DURABILITY,
        "food_properties": FOOD_PROPERTIES,
        "weapon_damage": WEAPON_DAMAGE,
        "smelting_recipes": SMELTING_RECIPES,
        "fuel_sources": FUEL_SOURCES,
    }

@app.get("/api/world/time", response_model=GameTime)
async def get_game_time():
    """Get the current in-game time."""
    tick = int(redis_client.get("game_time:tick") or 0)
    phase = redis_client.get("game_time:day_phase") or "day"
    return GameTime(
        tick=tick,
        phase=phase,
        full_cycle_ticks=FULL_CYCLE_TICKS
    )

@app.post("/api/player/create")
async def create_player(player_data: PlayerCreate):
    """Create a new player"""
    player_id = str(uuid.uuid4())
    username = player_data.username
    realm_id = player_data.realm_id
    character_data_json = json.dumps(player_data.character_data)
    
    try:
        conn = get_db_connection()
        cursor = conn.cursor()
        
        cursor.execute("""
            INSERT INTO players (id, username, realm_id, character_data)
            VALUES (%s, %s, %s, %s)
            RETURNING *
        """, (player_id, username, realm_id, character_data_json))
        
        player_data = cursor.fetchone()
        conn.commit()
        cursor.close()
        conn.close()
        
        return {"success": True, "player": dict(player_data)}
    
    except psycopg2.IntegrityError:
        raise HTTPException(status_code=400, detail="Username already exists")

@app.get("/api/player/{player_id}")
async def get_player(player_id: str):
    """Get player information"""
    conn = get_db_connection()
    cursor = conn.cursor()
    
    cursor.execute("SELECT * FROM players WHERE id = %s", (player_id,))
    player = cursor.fetchone()
    
    cursor.close()
    conn.close()
    
    if not player:
        raise HTTPException(status_code=404, detail="Player not found")
    
    return {"player": dict(player)}

@app.get("/api/world/chunk/{realm_id}/{chunk_x}/{chunk_z}")
async def get_chunk(realm_id: str, chunk_x: int, chunk_z: int):
    """Get or generate a world chunk"""
    conn = get_db_connection()
    cursor = conn.cursor()
    
    # Check if chunk exists in database
    cursor.execute("""
        SELECT * FROM world_chunks 
        WHERE chunk_x = %s AND chunk_z = %s AND realm_id = %s
    """, (chunk_x, chunk_z, realm_id))
    
    existing_chunk = cursor.fetchone()
    
    if existing_chunk:
        cursor.close()
        conn.close()
        return {"chunk": dict(existing_chunk)}
    
    # Generate new chunk
    new_chunk = world_gen.generate_chunk(chunk_x, chunk_z, realm_id)
    
    # Save to database
    cursor.execute("""
        INSERT INTO world_chunks (chunk_x, chunk_z, realm_id, blocks)
        VALUES (%s, %s, %s, %s)
        RETURNING *
    """, (chunk_x, chunk_z, realm_id, json.dumps(new_chunk.blocks)))
    
    saved_chunk = cursor.fetchone()
    conn.commit()
    cursor.close()
    conn.close()
    
    return {"chunk": dict(saved_chunk)}

@app.post("/api/world/build")
async def build_action(action: BuildAction):
    """Handle building/breaking blocks and update the world state."""
    realm_id = "default"  # Assuming default realm for now

    # Determine the new block type and the block being replaced/broken
    new_block_type = action.block_type if action.action == "place" else Block.AIR
    
    # Update the block in the world database
    replaced_block_type = await update_block_in_world(realm_id, action.x, action.y, action.z, new_block_type)

    if replaced_block_type is None:
        return {"success": False, "detail": "Block update failed. The block might not exist or is out of bounds."}

    # If breaking a block, add it to inventory
    if action.action == "break" and replaced_block_type != Block.AIR:
        conn = get_db_connection()
        cursor = conn.cursor()
        await add_item_to_player_inventory(action.player_id, replaced_block_type, 1, cursor)
        conn.commit()
        cursor.close()

    conn = get_db_connection()
    cursor = conn.cursor()
    # Log the action
    cursor.execute("""
        INSERT INTO build_actions (player_id, x, y, z, block_type, action, realm_id)
        VALUES (%s, %s, %s, %s, %s, %s, %s)
    """, (action.player_id, action.x, action.y, action.z, action.block_type if action.action == "place" else replaced_block_type, action.action, realm_id))
    conn.commit()
    cursor.close()
    conn.close()

    # Broadcast the world change to all players in the realm
    await manager.broadcast_to_realm(realm_id, {"type": "block_update", "x": action.x, "y": action.y, "z": action.z, "block_type": new_block_type})
    return {"success": True}

async def validate_player_for_websocket(player_id: str, realm_id: str):
    """Dependency to check if a player is valid and belongs to the realm before connecting."""
    conn = get_db_connection()
    cursor = conn.cursor()
    try:
        cursor.execute("SELECT realm_id FROM players WHERE id = %s", (player_id,))
        player_record = cursor.fetchone()

        # If player does not exist or realm does not match, reject the connection.
        # Raising HTTPException here sends a proper HTTP error before the WebSocket upgrade.
        if not player_record:
            raise HTTPException(status_code=404, detail="Player not found.")

        if player_record['realm_id'] != realm_id:
            raise HTTPException(status_code=403, detail="Player does not belong to this realm.")

    finally:
        cursor.close()
        conn.close()

# WebSocket endpoint
@app.websocket("/ws/{player_id}/{realm_id}")
async def websocket_endpoint(websocket: WebSocket, player_id: str, realm_id: str, _=Depends(validate_player_for_websocket)):
    await manager.connect(websocket, player_id, realm_id) # The dependency already validated the IDs
    
    try:
        while True:
            data = await websocket.receive_text()
            message = json.loads(data)
            
            if message["type"] == "player_move":
                # Update player position in Redis for real-time sync
                redis_client.hmset(f"player_pos:{player_id}", {
                    "x": message["x"],
                    "y": message["y"],
                    "z": message["z"],
                    "timestamp": datetime.now().isoformat()
                })
                
                # Get character data from Redis
                character_data_str = redis_client.hget(f"player:{player_id}", "character_data")
                character_data = json.loads(character_data_str) if character_data_str else {}

                # Broadcast position to other players
                await manager.broadcast_to_realm(realm_id, {
                    "type": "player_moved",
                    "player_id": player_id,
                    "x": message["x"],
                    "y": message["y"],
                    "z": message["z"],
                    "character_data": character_data
                }, exclude_player=player_id)
            
                # --- Fall Damage Logic ---
                x, y, z = float(message["x"]), float(message["y"]), float(message["z"])
                player_state_key = f"player_state:{player_id}"
                player_state = redis_client.hgetall(player_state_key)

                # Check the block directly below the player's feet
                block_below = await get_block_at(realm_id, int(x), int(y - 0.5), int(z))

                was_falling = player_state.get('is_falling') == 'true'
                is_on_ground = block_below != Block.AIR

                if not is_on_ground and not was_falling:
                    # Player just started falling
                    redis_client.hset(player_state_key, mapping={
                        "is_falling": "true",
                        "fall_start_y": str(y)
                    })
                elif is_on_ground and was_falling:
                    # Player just landed
                    fall_start_y = float(player_state.get('fall_start_y', str(y)))
                    fall_distance = fall_start_y - y
                    
                    # Damage is calculated for falls greater than 3 blocks
                    raw_damage = max(0, int(fall_distance - 3))
                    if raw_damage > 0:
                        await apply_damage_to_player(player_id, raw_damage)
                    # Reset falling state
                    redis_client.hset(player_state_key, "is_falling", "false")
            
            elif message["type"] == "chat":
                # Save chat message
                conn = get_db_connection()
                cursor = conn.cursor()
                
                cursor.execute("""
                    INSERT INTO chat_messages (player_id, message, realm_id)
                    VALUES (%s, %s, %s)
                """, (player_id, message["message"], realm_id))
                
                conn.commit()
                cursor.close()
                conn.close()
                
                # Broadcast chat message
                await manager.broadcast_to_realm(realm_id, {
                    "type": "chat_message",
                    "player_id": player_id,
                    "message": message["message"],
                    "timestamp": datetime.now().isoformat()
                })
            
            elif message["type"] == "break_block":
                # This handles real-time block breaking from the player
                conn = get_db_connection()
                cursor = conn.cursor()
                try:
                    x, y, z = int(message["x"]), int(message["y"]), int(message["z"])
                    held_item_key = message.get("held_item_key")

                    target_block_type = await get_block_at(realm_id, x, y, z)
                    if target_block_type is None or target_block_type == Block.AIR:
                        raise Exception("Nothing to break")

                    # --- Special drops (seeds from grass) ---
                    if target_block_type == Block.GRASS:
                        if np.random.rand() < 0.125: # 12.5% chance
                            await add_item_to_player_inventory(player_id, Block.WHEAT_SEEDS, 1, cursor)

                    # --- Crop Harvesting ---
                    if target_block_type == Block.WHEAT_CROP:
                        cursor.execute("SELECT state FROM block_entities WHERE x=%s AND y=%s AND z=%s AND realm_id=%s FOR UPDATE", (x, y, z, realm_id))
                        crop_record = cursor.fetchone()
                        if crop_record:
                            state = crop_record['state']
                            props = CROP_PROPERTIES[str(Block.WHEAT_CROP)]
                            if state.get('stage', 0) >= props['max_stage']:
                                # Fully grown: drop wheat and seeds
                                await add_item_to_player_inventory(player_id, props['drops']['item'], np.random.randint(*props['drops']['quantity']) + 1, cursor)
                                await add_item_to_player_inventory(player_id, props['seed_drops']['item'], np.random.randint(*props['seed_drops']['quantity']) + 1, cursor)
                            else:
                                # Not fully grown: drop one seed
                                await add_item_to_player_inventory(player_id, props['seed_item'], 1, cursor)
                            cursor.execute("DELETE FROM block_entities WHERE x=%s AND y=%s AND z=%s AND realm_id=%s", (x, y, z, realm_id))

                    # If breaking a furnace, retrieve its contents to drop them
                    if target_block_type == Block.FURNACE:
                        cursor.execute("SELECT state FROM block_entities WHERE x=%s AND y=%s AND z=%s AND realm_id=%s FOR UPDATE", (x, y, z, realm_id))
                        furnace_record = cursor.fetchone()
                        if furnace_record:
                            state = furnace_record['state']
                            for slot in ['input', 'fuel', 'output']:
                                if slot in state and state[slot].get('quantity', 0) > 0:
                                    await add_item_to_player_inventory(player_id, state[slot]['item_id'], state[slot]['quantity'], cursor)
                            cursor.execute("DELETE FROM block_entities WHERE x=%s AND y=%s AND z=%s AND realm_id=%s", (x, y, z, realm_id))

                    # --- Tool and Tier Checking ---
                    cursor.execute("SELECT inventory, equipment FROM players WHERE id = %s FOR UPDATE", (player_id,))
                    player_record = cursor.fetchone()
                    inventory = player_record['inventory']
                    equipment = player_record['equipment']
                    held_item_id_str, player_tool_tier, is_tool = None, 0, False

                    if held_item_key and held_item_key in inventory:
                        item_data = inventory[held_item_key]
                        if "item_id" in item_data:
                            held_item_id_str = str(item_data["item_id"])
                            is_tool = held_item_id_str in TOOL_DURABILITY
                    
                    if is_tool: player_tool_tier = TOOL_TIERS.get(held_item_id_str, 0)
                    
                    block_props = BLOCK_MINING_PROPERTIES.get(str(target_block_type))
                    required_tier = block_props.get("required_tier", 0) if block_props else 0

                    if player_tool_tier < required_tier:
                        raise Exception("You need a better tool to mine this.")

                    # --- Block Breaking and Durability ---
                    broken_block_type = await update_block_in_world(realm_id, x, y, z, Block.AIR)
                    if broken_block_type is None: raise Exception("Failed to break block.")

                    item_to_drop = block_props.get("drops", broken_block_type) if block_props else broken_block_type
                    inventory = await add_item_to_player_inventory(player_id, item_to_drop, 1, cursor)

                    if is_tool:
                        inventory[held_item_key]["durability"] -= 1
                        if inventory[held_item_key]["durability"] <= 0:
                            # Tool broke, remove from inventory and equipment
                            del inventory[held_item_key]
                            for slot, key in list(equipment.items()):
                                if key == held_item_key:
                                    del equipment[slot]
                    
                    cursor.execute("UPDATE players SET inventory = %s, equipment = %s WHERE id = %s", (json.dumps(inventory), json.dumps(equipment), player_id))
                    cursor.execute("INSERT INTO build_actions (player_id, x, y, z, block_type, action, realm_id) VALUES (%s, %s, %s, %s, %s, %s, %s)", (player_id, x, y, z, broken_block_type, "break", realm_id))
                    conn.commit()

                    await manager.broadcast_to_realm(realm_id, {"type": "block_update", "x": x, "y": y, "z": z, "block_type": Block.AIR}, exclude_player=player_id)
                    await manager.send_to_player(player_id, {"type": "inventory_update", "inventory": inventory})

                except Exception as e:
                    conn.rollback()
                    await manager.send_to_player(player_id, {"type": "action_failed", "reason": str(e)})
                finally:
                    cursor.close()
                    conn.close()

            elif message["type"] == "attack_monster":
                monster_id = message.get("monster_id")
                if monster_id and monster_id in active_monsters:
                    conn = get_db_connection()
                    cursor = conn.cursor()
                    try:
                        held_item_key = message.get("held_item_key")
                        monster = active_monsters[monster_id]

                        cursor.execute("SELECT inventory, equipment FROM players WHERE id = %s FOR UPDATE", (player_id,))
                        player_record = cursor.fetchone()
                        inventory = player_record['inventory']
                        equipment = player_record['equipment']

                        held_item_id_str, is_weapon = None, False
                        player_damage = BARE_HAND_DAMAGE

                        # Determine damage based on held item
                        if held_item_key and held_item_key in inventory:
                            item_data = inventory[held_item_key]
                            if "item_id" in item_data:
                                held_item_id_str = str(item_data["item_id"])
                                is_weapon = held_item_id_str in WEAPON_DAMAGE

                        if is_weapon:
                            player_damage = WEAPON_DAMAGE[held_item_id_str]

                        monster.health -= player_damage

                        # Apply durability loss
                        if is_weapon and held_item_id_str in TOOL_DURABILITY:
                            inventory[held_item_key]["durability"] -= 1
                            if inventory[held_item_key]["durability"] <= 0:
                                del inventory[held_item_key]
                                for slot, key in list(equipment.items()):
                                    if key == held_item_key: del equipment[slot]
                        
                        cursor.execute("UPDATE players SET inventory = %s, equipment = %s WHERE id = %s", (json.dumps(inventory), json.dumps(equipment), player_id))
                        conn.commit()
                        
                        if monster.health <= 0:
                            # Monster died
                            del active_monsters[monster_id]

                            # --- Loot Drop Logic ---
                            loot_table = MONSTER_LOOT_TABLES.get(monster.monster_type, [])
                            
                            for item_spec in loot_table:
                                if np.random.rand() < item_spec["chance"]:
                                    quantity_range = item_spec["quantity"]
                                    quantity = np.random.randint(quantity_range[0], quantity_range[1] + 1)
                                    if quantity > 0:
                                        await add_item_to_player_inventory(player_id, item_spec["item_id"], quantity, cursor)
                            conn.commit()

                            cursor.execute("SELECT inventory FROM players WHERE id = %s", (player_id,))
                            if player_record:
                                await manager.send_to_player(player_id, {"type": "inventory_update", "inventory": player_record['inventory']})
                            # --- End Loot Drop Logic ---

                            await manager.broadcast_to_realm(realm_id, {
                                "type": "monster_died",
                                "monster_id": monster_id
                            })
                        else:
                            # Broadcast that the monster took damage
                            await manager.broadcast_to_realm(realm_id, {
                                "type": "entity_health_update",
                                "entity_id": monster_id,
                                "entity_type": "monster",
                                "current_health": monster.health,
                                "max_health": MONSTER_STATS[monster.monster_type]["health"]
                            })
                    finally:
                        cursor.close()
                        conn.close()

            elif message["type"] == "craft_item":
                item_id_to_craft = str(message.get("item_id"))
                
                updated_inventory = await process_crafting(player_id, item_id_to_craft)

                if updated_inventory is not None:
                    # Crafting was successful
                    await manager.send_to_player(player_id, {
                        "type": "inventory_update",
                        "inventory": updated_inventory
                    })
                else:
                    # Crafting failed (e.g., missing ingredients)
                    await manager.send_to_player(player_id, {
                        "type": "action_failed",
                        "reason": "Crafting failed. Not enough ingredients."
                    })

            elif message["type"] == "repair_item":
                conn = get_db_connection()
                cursor = conn.cursor()
                try:
                    item_key_1 = message.get("item_key_1")
                    item_key_2 = message.get("item_key_2")

                    if not item_key_1 or not item_key_2 or item_key_1 == item_key_2:
                        raise Exception("Invalid items selected for repair.")

                    cursor.execute("SELECT inventory FROM players WHERE id = %s FOR UPDATE", (player_id,))
                    inventory = cursor.fetchone()['inventory']

                    # Verify items exist and are the same type
                    if item_key_1 not in inventory or item_key_2 not in inventory:
                        raise Exception("One or both items not found in inventory.")

                    tool1 = inventory[item_key_1]
                    tool2 = inventory[item_key_2]

                    if tool1.get("item_id") != tool2.get("item_id"):
                        raise Exception("Items must be of the same type to be repaired.")

                    item_id_str = str(tool1.get("item_id"))
                    if item_id_str not in TOOL_DURABILITY:
                        raise Exception("This item cannot be repaired.")

                    # Get durabilities and max durability
                    durability1 = tool1.get("durability", 0)
                    durability2 = tool2.get("durability", 0)
                    max_durability = TOOL_DURABILITY[item_id_str]

                    # Remove old items
                    del inventory[item_key_1]
                    del inventory[item_key_2]

                    # Calculate new durability and create new item
                    new_durability = durability1 + durability2 + int(max_durability * REPAIR_BONUS)
                    new_durability = min(new_durability, max_durability) # Cap at max

                    new_instance_id = str(uuid.uuid4())
                    inventory[new_instance_id] = {"item_id": int(item_id_str), "durability": new_durability}

                    cursor.execute("UPDATE players SET inventory = %s WHERE id = %s", (json.dumps(inventory), player_id))
                    conn.commit()
                    await manager.send_to_player(player_id, {"type": "inventory_update", "inventory": inventory})
                except Exception as e:
                    conn.rollback()
                    await manager.send_to_player(player_id, {"type": "action_failed", "reason": str(e)})
                finally:
                    cursor.close()
                    conn.close()

            elif message["type"] == "equip_armor":
                conn = get_db_connection()
                cursor = conn.cursor()
                try:
                    item_key_to_equip = message.get("inventory_key")
                    if not item_key_to_equip: raise Exception("No item specified.")

                    cursor.execute("SELECT inventory, equipment FROM players WHERE id = %s FOR UPDATE", (player_id,))
                    player_record = cursor.fetchone()
                    inventory = player_record['inventory']
                    equipment = player_record['equipment']

                    if item_key_to_equip not in inventory: raise Exception("Item not in inventory.")

                    item_data = inventory[item_key_to_equip]
                    item_id_str = str(item_data.get("item_id"))

                    slot_type = None
                    if item_id_str == str(Block.IRON_HELMET): slot_type = "helmet"
                    elif item_id_str == str(Block.IRON_CHESTPLATE): slot_type = "chestplate"
                    elif item_id_str == str(Block.IRON_LEGGINGS): slot_type = "leggings"
                    elif item_id_str == str(Block.IRON_BOOTS): slot_type = "boots"
                    
                    if not slot_type: raise Exception("This item is not an armor piece.")

                    # The old item (if any) is automatically unequipped by overwriting the slot
                    equipment[slot_type] = item_key_to_equip

                    cursor.execute("UPDATE players SET equipment = %s WHERE id = %s", (json.dumps(equipment), player_id))
                    conn.commit()

                    await manager.send_to_player(player_id, {"type": "equipment_update", "inventory": inventory, "equipment": equipment})
                except Exception as e:
                    conn.rollback()
                    await manager.send_to_player(player_id, {"type": "action_failed", "reason": str(e)})
                finally:
                    cursor.close()
                    conn.close()

            elif message["type"] == "unequip_armor":
                conn = get_db_connection()
                cursor = conn.cursor()
                try:
                    slot_to_unequip = message.get("slot")
                    if not slot_to_unequip in ["helmet", "chestplate", "leggings", "boots"]: raise Exception("Invalid slot.")

                    cursor.execute("SELECT equipment FROM players WHERE id = %s FOR UPDATE", (player_id,))
                    equipment = cursor.fetchone()['equipment']

                    if slot_to_unequip in equipment:
                        del equipment[slot_to_unequip]
                        cursor.execute("UPDATE players SET equipment = %s WHERE id = %s", (json.dumps(equipment), player_id))
                        conn.commit()
                        await manager.send_to_player(player_id, {"type": "equipment_update", "equipment": equipment})
                finally:
                    cursor.close()
                    conn.close()

            elif message["type"] == "eat_food":
                conn = get_db_connection()
                cursor = conn.cursor()
                try:
                    inventory_key = message.get("inventory_key")
                    if not inventory_key: raise Exception("No food item specified.")

                    cursor.execute("SELECT inventory, hunger, saturation, health FROM players WHERE id = %s FOR UPDATE", (player_id,))
                    player_record = cursor.fetchone()
                    inventory = player_record['inventory']
                    
                    if inventory_key not in inventory: raise Exception("Item not in inventory.")
                    
                    item_to_eat = inventory[inventory_key]
                    item_id_str = str(item_to_eat.get('item_id')) if 'item_id' in item_to_eat else inventory_key

                    food_props = FOOD_PROPERTIES.get(item_id_str)
                    if not food_props: raise Exception("This item is not edible.")

                    # Consume item
                    if 'quantity' in item_to_eat:
                        item_to_eat['quantity'] -= 1
                        if item_to_eat['quantity'] <= 0: del inventory[inventory_key]
                    else:
                        del inventory[inventory_key]

                    # Restore hunger and saturation
                    new_hunger = min(20, player_record['hunger'] + food_props['hunger'])
                    new_saturation = min(new_hunger, player_record['saturation'] + food_props['saturation'])

                    cursor.execute(
                        "UPDATE players SET inventory = %s, hunger = %s, saturation = %s WHERE id = %s",
                        (json.dumps(inventory), new_hunger, new_saturation, player_id)
                    )
                    conn.commit()

                    await manager.send_to_player(player_id, {"type": "inventory_update", "inventory": inventory})
                    await manager.send_to_player(player_id, {
                        "type": "player_stats_update", "health": player_record['health'],
                        "hunger": new_hunger, "saturation": new_saturation
                    })
                except Exception as e:
                    conn.rollback()
                    await manager.send_to_player(player_id, {"type": "action_failed", "reason": str(e)})
                finally:
                    cursor.close()
                    conn.close()
            
            elif message["type"] == "interact_with_block":
                conn = get_db_connection()
                cursor = conn.cursor()
                try:
                    x, y, z = int(message["x"]), int(message["y"]), int(message["z"])
                    held_item_key = message.get("held_item_key")

                    target_block_type = await get_block_at(realm_id, x, y, z)
                    
                    cursor.execute("SELECT inventory, equipment FROM players WHERE id = %s FOR UPDATE", (player_id,))
                    player_record = cursor.fetchone()
                    inventory = player_record['inventory']
                    equipment = player_record['equipment']

                    held_item_id_str = None
                    if held_item_key and held_item_key in inventory:
                        item_data = inventory[held_item_key]
                        held_item_id_str = str(item_data.get('item_id')) if 'item_id' in item_data else held_item_key

                    # --- Hoe Logic: Tilling soil ---
                    if held_item_id_str == str(Block.WOODEN_HOE) and target_block_type in [Block.GRASS, Block.DIRT]:
                        await update_block_in_world(realm_id, x, y, z, Block.FARMLAND)
                        cursor.execute("INSERT INTO block_entities (x, y, z, realm_id, block_type, state) VALUES (%s, %s, %s, %s, %s, %s) ON CONFLICT DO NOTHING", (x, y, z, realm_id, Block.FARMLAND, json.dumps({})))
                        
                        # Durability loss
                        inventory[held_item_key]['durability'] -= 1
                        if inventory[held_item_key]['durability'] <= 0:
                            del inventory[held_item_key]
                            for slot, key in list(equipment.items()):
                                if key == held_item_key: del equipment[slot]
                        
                        cursor.execute("UPDATE players SET inventory = %s, equipment = %s WHERE id = %s", (json.dumps(inventory), json.dumps(equipment), player_id))
                        await manager.broadcast_to_realm(realm_id, {"type": "block_update", "x": x, "y": y, "z": z, "block_type": Block.FARMLAND})

                    # --- Planting Seeds Logic ---
                    elif held_item_id_str == str(Block.WHEAT_SEEDS) and target_block_type == Block.FARMLAND:
                        block_above = await get_block_at(realm_id, x, y + 1, z)
                        if block_above == Block.AIR:
                            # Consume one seed
                            inventory[held_item_id_str]['quantity'] -= 1
                            if inventory[held_item_id_str]['quantity'] <= 0: del inventory[held_item_id_str]
                            
                            # Place crop and create entity
                            await update_block_in_world(realm_id, x, y + 1, z, Block.WHEAT_CROP)
                            crop_state = {"stage": 0}
                            cursor.execute("INSERT INTO block_entities (x, y, z, realm_id, block_type, state) VALUES (%s, %s, %s, %s, %s, %s)", (x, y + 1, z, realm_id, Block.WHEAT_CROP, json.dumps(crop_state)))
                            
                            cursor.execute("UPDATE players SET inventory = %s WHERE id = %s", (json.dumps(inventory), player_id))
                            await manager.broadcast_to_realm(realm_id, {"type": "block_update", "x": x, "y": y + 1, "z": z, "block_type": Block.WHEAT_CROP})
                        else:
                            raise Exception("Not enough space to plant.")
                    
                    # --- Fallback to block entity interaction ---
                    elif target_block_type == Block.FURNACE:
                        cursor.execute("SELECT state, block_type FROM block_entities WHERE x=%s AND y=%s AND z=%s AND realm_id=%s", (x, y, z, realm_id))
                        record = cursor.fetchone()
                        if record:
                            await manager.send_to_player(player_id, {"type": "block_entity_state", "x": x, "y": y, "z": z, "block_type": record['block_type'], "state": record['state']})

                    conn.commit()
                    await manager.send_to_player(player_id, {"type": "inventory_update", "inventory": inventory})
                except Exception as e:
                    conn.rollback()
                    await manager.send_to_player(player_id, {"type": "action_failed", "reason": str(e)})
                finally:
                    cursor.close()
                    conn.close()

            elif message["type"] == "interact_with_block_entity":
                x, y, z = int(message["x"]), int(message["y"]), int(message["z"])
                conn = get_db_connection()
                cursor = conn.cursor()
                cursor.execute("SELECT state, block_type FROM block_entities WHERE x=%s AND y=%s AND z=%s AND realm_id=%s", (x, y, z, realm_id))
                record = cursor.fetchone()
                cursor.close()
                conn.close()
                if record:
                    redis_client.set(f"player_interaction:{player_id}", json.dumps({"x":x, "y":y, "z":z}))
                    await manager.send_to_player(player_id, {
                        "type": "block_entity_state",
                        "x": x, "y": y, "z": z,
                        "block_type": record['block_type'],
                        "state": record['state']
                    })

            elif message["type"] == "furnace_add_item":
                conn = get_db_connection()
                cursor = conn.cursor()
                try:
                    x, y, z = int(message["x"]), int(message["y"]), int(message["z"])
                    slot = message["slot"]  # "input" or "fuel"
                    inventory_key = message["inventory_key"]

                    cursor.execute("SELECT inventory FROM players WHERE id = %s FOR UPDATE", (player_id,))
                    inventory = cursor.fetchone()['inventory']
                    
                    cursor.execute("SELECT state FROM block_entities WHERE x=%s AND y=%s AND z=%s AND realm_id=%s FOR UPDATE", (x, y, z, realm_id))
                    furnace_state = cursor.fetchone()['state']

                    if inventory_key not in inventory: raise Exception("Item not in inventory")
                    
                    item_to_move = inventory[inventory_key]
                    item_id_str = str(item_to_move.get('item_id')) if 'item_id' in item_to_move else inventory_key

                    if slot in furnace_state and str(furnace_state[slot]['item_id']) != item_id_str:
                        raise Exception("Furnace slot occupied by different item")

                    if 'quantity' in item_to_move:
                        item_to_move['quantity'] -= 1
                        if item_to_move['quantity'] <= 0: del inventory[inventory_key]
                    else: # Should not happen for furnace inputs, but good practice
                        del inventory[inventory_key]
                    
                    if slot not in furnace_state or furnace_state[slot].get('quantity', 0) == 0:
                        furnace_state[slot] = {'item_id': int(item_id_str), 'quantity': 1}
                    else:
                        furnace_state[slot]['quantity'] += 1
                        
                    cursor.execute("UPDATE players SET inventory = %s WHERE id = %s", (json.dumps(inventory), player_id))
                    cursor.execute("UPDATE block_entities SET state = %s WHERE x=%s AND y=%s AND z=%s AND realm_id=%s", (json.dumps(furnace_state), x, y, z, realm_id))
                    conn.commit()
                    
                    await manager.send_to_player(player_id, {"type": "inventory_update", "inventory": inventory})
                    await manager.send_to_player(player_id, {"type": "block_entity_state", "x":x, "y":y, "z":z, "block_type": Block.FURNACE, "state": furnace_state})

                except Exception as e:
                    conn.rollback()
                    await manager.send_to_player(player_id, {"type": "action_failed", "reason": str(e)})
                finally:
                    cursor.close()
                    conn.close()

            elif message["type"] == "furnace_take_output":
                conn = get_db_connection()
                cursor = conn.cursor()
                try:
                    x, y, z = int(message["x"]), int(message["y"]), int(message["z"])
                    cursor.execute("SELECT state FROM block_entities WHERE x=%s AND y=%s AND z=%s AND realm_id=%s FOR UPDATE", (x, y, z, realm_id))
                    furnace_state = cursor.fetchone()['state']
                    
                    if 'output' not in furnace_state or furnace_state['output']['quantity'] <= 0:
                        raise Exception("No items to take")
                        
                    output_item = furnace_state['output']
                    inventory = await add_item_to_player_inventory(player_id, output_item['item_id'], output_item['quantity'], cursor)
                    
                    del furnace_state['output']
                    cursor.execute("UPDATE block_entities SET state = %s WHERE x=%s AND y=%s AND z=%s AND realm_id=%s", (json.dumps(furnace_state), x, y, z, realm_id))
                    conn.commit()
                    
                    await manager.send_to_player(player_id, {"type": "inventory_update", "inventory": inventory})
                    await manager.send_to_player(player_id, {"type": "block_entity_state", "x":x, "y":y, "z":z, "block_type": Block.FURNACE, "state": furnace_state})
                except Exception as e:
                    conn.rollback()
                    await manager.send_to_player(player_id, {"type": "action_failed", "reason": str(e)})
                finally:
                    cursor.close()
                    conn.close()

            elif message["type"] == "place_block":
                conn = get_db_connection()
                cursor = conn.cursor()
                try:
                    x, y, z = int(message["x"]), int(message["y"]), int(message["z"])
                    block_type_to_place = int(message["block_type"])

                    new_inventory = await remove_item_from_player_inventory(player_id, block_type_to_place, 1, cursor)
                    if new_inventory is None: raise Exception("Item not in inventory.")

                    replaced_block_type = await update_block_in_world(realm_id, x, y, z, block_type_to_place)
                    if replaced_block_type != Block.AIR: raise Exception("Cannot place block here.")

                    if block_type_to_place == Block.FURNACE:
                        cursor.execute("INSERT INTO block_entities (x, y, z, realm_id, block_type, state) VALUES (%s, %s, %s, %s, %s, %s)", (x, y, z, realm_id, Block.FURNACE, json.dumps({})))

                    cursor.execute("INSERT INTO build_actions (player_id, x, y, z, block_type, action, realm_id) VALUES (%s, %s, %s, %s, %s, %s, %s)", (player_id, x, y, z, block_type_to_place, "place", realm_id))
                    conn.commit()

                    await manager.broadcast_to_realm(realm_id, {"type": "block_update", "x": x, "y": y, "z": z, "block_type": block_type_to_place})
                    await manager.send_to_player(player_id, {"type": "inventory_update", "inventory": new_inventory})
                except Exception as e:
                    conn.rollback()
                    await manager.send_to_player(player_id, {"type": "action_failed", "reason": str(e)})
                finally:
                    cursor.close()
                    conn.close()
    except WebSocketDisconnect:
        manager.disconnect(player_id)

@app.on_event("startup")
async def startup_event():
    """Initialize database and start background tasks on startup"""
    init_database()
    
    # Initialize game time in Redis if it doesn't exist
    if not redis_client.exists("game_time:tick"):
        redis_client.set("game_time:tick", 0)
    if not redis_client.exists("game_time:day_phase"):
        redis_client.set("game_time:day_phase", "day")
        
    # Start the background task for the day/night cycle
    print("Starting background tasks...")
    asyncio.create_task(game_time_ticker())
    asyncio.create_task(monster_spawner())
    asyncio.create_task(monster_ai_ticker())
    asyncio.create_task(furnace_ticker())
    asyncio.create_task(player_stats_ticker())
    asyncio.create_task(farming_ticker())
    
    print("MMORPG Backend Server started successfully!")

@app.get("/")
async def root():
    return {"message": "MMORPG Backend API", "version": "1.0.0"}

if __name__ == "__main__":
    import uvicorn
    uvicorn.run(app, host="0.0.0.0", port=8000)