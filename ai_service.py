import os
import json
from typing import Dict, List, Optional
from datetime import datetime
from langchain.schema import HumanMessage, SystemMessage
from langchain_community.chat_models import ChatOllama
from langchain.memory import ConversationBufferMemory
from fastapi import FastAPI, HTTPException
from pydantic import BaseModel
import uvicorn

# Models
class NPCInteraction(BaseModel):
    npc_id: str
    npc_type: str  # "trader", "quest_giver", "villager", "guard"
    player_id: str
    player_message: str
    context: Dict = {}  # Game context like player level, inventory, location

class NPCResponse(BaseModel):
    npc_id: str
    response: str
    actions: List[Dict] = []  # Actions like give_item, start_quest, etc.
    mood: str = "neutral"  # happy, angry, excited, etc.

# NPC AI Service
class NPCAIService:
    def __init__(self):
        # Use Ollama for local LLM inference
        self.llm = ChatOllama(
            model=os.getenv("OLLAMA_MODEL", "llama2"), # Default to llama2, can be changed
            base_url=os.getenv("OLLAMA_BASE_URL", "http://localhost:11434"),
            temperature=0.7,
        )
        self.memories: Dict[str, ConversationBufferMemory] = {}
        
        # NPC personalities and roles
        self.npc_personas = {
            "trader": {
                "personality": "A shrewd merchant who loves to bargain. Always looking for profit but fair in dealings. Knows about rare materials and their uses.",
                "greeting": "Welcome, traveler! I have the finest wares in all the realm. What might interest you today?",
                "interests": ["trading", "rare materials", "profit", "market news"]
            },
            "quest_giver": {
                "personality": "A wise elder who knows the ancient secrets of the land. Speaks in riddles sometimes but genuinely wants to help adventurers grow stronger.",
                "greeting": "Ah, another soul seeking purpose. I may have a task worthy of your skills.",
                "interests": ["ancient lore", "helping heroes", "mysterious artifacts", "protecting the realm"]
            },
            "villager": {
                "personality": "A friendly local who knows gossip and daily life in the area. Simple but kind-hearted, always willing to share local knowledge.",
                "greeting": "Hello there! Nice to see a new face around these parts. How can I help?",
                "interests": ["local news", "daily life", "weather", "community events"]
            },
            "guard": {
                "personality": "A dutiful protector who takes security seriously but has a soft spot for genuine travelers. Military background shows in speech patterns.",
                "greeting": "State your business, traveler. These are peaceful lands, and we aim to keep them that way.",
                "interests": ["security", "law and order", "protecting citizens", "military tactics"]
            }
        }
    
    def get_memory(self, npc_id: str, player_id: str) -> ConversationBufferMemory:
        """Get or create conversation memory for NPC-player pair"""
        memory_key = f"{npc_id}_{player_id}"
        if memory_key not in self.memories:
            self.memories[memory_key] = ConversationBufferMemory(return_messages=True)
        return self.memories[memory_key]
    
    def create_system_prompt(self, npc_type: str, context: Dict) -> str:
        """Create system prompt based on NPC type and game context"""
        persona = self.npc_personas.get(npc_type, self.npc_personas["villager"])
        
        prompt = f"""You are an NPC in a Minecraft-style MMORPG game. Your role is: {npc_type}

PERSONALITY: {persona['personality']}

CURRENT GAME CONTEXT:
- Player Location: {context.get('location', 'unknown area')}
- Player Level: {context.get('level', 1)}
- Player Inventory: {context.get('inventory', {})}
- Time of Day: {context.get('time', 'day')}
- Weather: {context.get('weather', 'clear')}

IMPORTANT RULES:
1. Stay in character as this NPC type
2. Keep responses under 100 words
3. Reference the game world naturally
4. If appropriate for your role, you can:
   - Offer trades (if trader)
   - Give quests (if quest giver)
   - Share local information (if villager)
   - Provide security updates (if guard)

5. End responses with actions in JSON format if needed:
   {{
     "actions": [
       {{"type": "offer_trade", "item": "iron_sword", "price": 50}},
       {{"type": "give_quest", "quest_id": "collect_wood", "description": "Bring me 10 oak logs"}}
     ],
     "mood": "happy"
   }}

Respond naturally to the player's message while maintaining your character."""

        return prompt
    
    async def generate_npc_response(self, interaction: NPCInteraction) -> NPCResponse:
        """Generate NPC response using LangChain and Google Gemini"""
        try:
            memory = self.get_memory(interaction.npc_id, interaction.player_id)
            system_prompt = self.create_system_prompt(interaction.npc_type, interaction.context)
            
            messages = [SystemMessage(content=system_prompt)]
            
            # Add conversation history
            history = memory.chat_memory.messages
            messages.extend(history[-6:])  # Last 3 exchanges to keep context manageable
            
            # Add current player message
            messages.append(HumanMessage(content=interaction.player_message))
            
            # Generate response
            response = await self.llm.ainvoke(messages)
            response_text = response.content
            
            # Save to memory
            memory.chat_memory.add_user_message(interaction.player_message)
            memory.chat_memory.add_ai_message(response_text)
            
            # Parse actions and mood if present
            actions = []
            mood = "neutral"
            
            try:
                # Look for JSON in the response
                if "{" in response_text and "}" in response_text:
                    json_start = response_text.find("{")
                    json_end = response_text.rfind("}") + 1
                    json_str = response_text[json_start:json_end]
                    
                    parsed = json.loads(json_str)
                    actions = parsed.get("actions", [])
                    mood = parsed.get("mood", "neutral")
                    
                    # Remove JSON from response text
                    response_text = response_text[:json_start].strip()
            
            except json.JSONDecodeError:
                pass  # No valid JSON found, that's okay
            
            return NPCResponse(
                npc_id=interaction.npc_id,
                response=response_text,
                actions=actions,
                mood=mood
            )
        
        except Exception as e:
            # Fallback response
            persona = self.npc_personas.get(interaction.npc_type, self.npc_personas["villager"])
            return NPCResponse(
                npc_id=interaction.npc_id,
                response=f"*The {interaction.npc_type} seems distracted* {persona['greeting']}",
                actions=[],
                mood="neutral"
            )

# FastAPI app for AI service
app = FastAPI(title="MMORPG AI Service", version="1.0.0")
ai_service = NPCAIService()

@app.post("/npc/interact", response_model=NPCResponse)
async def npc_interact(interaction: NPCInteraction):
    """Handle NPC interaction"""
    return await ai_service.generate_npc_response(interaction)

@app.post("/npc/generate_quest")
async def generate_quest(npc_type: str, difficulty: str = "normal", theme: str = "general"):
    """Generate a dynamic quest"""
    try:
        system_prompt = f"""You are a {npc_type} NPC in a Minecraft-style game. Generate a {difficulty} difficulty quest with a {theme} theme.

Return ONLY a JSON object with this structure:
{{
  "title": "Quest Name",
  "description": "What the player needs to do",
  "objectives": ["objective 1", "objective 2"],
  "rewards": {{"experience": 100, "items": ["iron_ingot", "gold_coin"]}},
  "estimated_time": "15 minutes"
}}"""
        
        response = await ai_service.llm.ainvoke([SystemMessage(content=system_prompt)])
        
        try:
            quest_data = json.loads(response.content)
            return {"success": True, "quest": quest_data}
        except json.JSONDecodeError:
            return {"success": False, "error": "Could not generate valid quest"}
    
    except Exception as e:
        return {"success": False, "error": str(e)}

@app.get("/npc/personalities")
async def get_npc_personalities():
    """Get available NPC types and their personalities"""
    return {"personalities": ai_service.npc_personas}

@app.get("/")
async def root():
    return {"message": "MMORPG AI Service", "version": "1.0.0"}

if __name__ == "__main__":
    uvicorn.run(app, host="0.0.0.0", port=8001)