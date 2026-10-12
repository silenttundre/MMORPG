import asyncio
import json
import requests
import websockets
from pynput import keyboard
import threading
import uuid

# --- Configuration ---
# On the host computer, this can be "localhost".
# On other players' computers, this MUST be the host's Local IP address (e.g., "192.168.1.15").
HOST_IP = "localhost"
BACKEND_URL = f"http://{HOST_IP}:8000"
WEBSOCKET_URL = f"ws://{HOST_IP}:8000"

# --- Player State ---
player_id = None
realm_id = "default"
x, y, z = 0.0, 0.0, 0.0
websocket_client = None
is_connected = False

def create_player(username):
    """Create a new player via API"""
    global player_id
    try:
        payload = {"username": username, "realm_id": realm_id}
        response = requests.post(f"{BACKEND_URL}/api/player/create", json=payload)
        response.raise_for_status()
        player_data = response.json()
        if player_data.get("success"):
            player_id = player_data["player"]["id"]
            print(f"Player '{username}' created with ID: {player_id}")
            return True
        else:
            print(f"Error creating player: {player_data.get('detail')}")
            return False
    except requests.exceptions.HTTPError as http_err:
        # Handle specific HTTP errors, like 400 Bad Request
        if http_err.response.status_code == 400:
            try:
                error_detail = http_err.response.json().get("detail")
                if "Username already exists" in str(error_detail):
                    print(f"[ERROR] The username '{username}' is already taken. Please choose another.")
                    return False
            except json.JSONDecodeError:
                # If the response isn't JSON, fall through to the generic error
                pass
        print(f"Could not create player: {http_err}")
        return False
    except requests.exceptions.RequestException as e:
        print(f"Could not connect to backend to create player: {e}")
        return False

async def send_movement(dx, dy, dz):
    """Send player movement to the server"""
    global x, y, z
    if websocket_client and is_connected:
        x += dx
        y += dy
        z += dz
        message = {
            "type": "player_move",
            "x": x,
            "y": y,
            "z": z
        }
        await websocket_client.send(json.dumps(message))
        print(f"Moved to ({x:.1f}, {y:.1f}, {z:.1f})")

async def listen_to_server(ws):
    """Listen for incoming messages from the server"""
    global x, y, z
    print("Listening for server messages...")
    try:
        async for message in ws:
            data = json.loads(message)
            msg_type = data.get("type")
            if msg_type == "player_moved":
                if data.get("player_id") != player_id:
                    print(f"\n[SERVER] Player {data['player_id'][:8]} moved to ({data['x']:.1f}, {data['y']:.1f}, {data['z']:.1f})")
            elif msg_type == "chat_message":
                print(f"\n[CHAT] {data['player_id'][:8]}: {data['message']}")
            elif msg_type == "player_respawn":
                print("\n[!!] You have died and respawned! [!!]")
                respawn_data = data.get("data", {})
                x = respawn_data.get("x", 0.0)
                y = respawn_data.get("y", 0.0)
                z = respawn_data.get("z", 0.0)
                print(f"Respawned at ({x:.1f}, {y:.1f}, {z:.1f})")
            else:
                print(f"\n[SERVER] {data}")
    except websockets.exceptions.ConnectionClosed as e:
        print(f"Connection to server closed: {e}")
    finally:
        global is_connected
        is_connected = False

async def connect_to_game():
    """Main function to connect to the WebSocket and start listening"""
    global websocket_client, is_connected
    if not player_id:
        print("Player not created. Cannot connect.")
        return

    uri = f"{WEBSOCKET_URL}/ws/{player_id}/{realm_id}"
    try:
        async with websockets.connect(uri) as ws:
            websocket_client = ws
            is_connected = True
            print(f"Successfully connected to realm '{realm_id}'. You can now move around!")
            print("Use W/S for Z-axis, A/D for X-axis, Q/E for Y-axis. Press ESC to quit.")
            
            # Start listening for server messages in the background
            await listen_to_server(ws)

    except Exception as e:
        print(f"Failed to connect to WebSocket: {e}")
        is_connected = False

# --- Keyboard Input Handling ---
def start_keyboard_listener(loop: asyncio.AbstractEventLoop):
    """Starts the pynput keyboard listener in a separate thread."""

    def on_press(key):
        """
        Handles key presses and schedules the corresponding coroutine on the main event loop.
        This function is executed in the listener's thread.
        """
        if not is_connected:
            return

        coro = None
        try:
            if key.char == 'w': coro = send_movement(0, 0, 1)
            elif key.char == 's': coro = send_movement(0, 0, -1)
            elif key.char == 'a': coro = send_movement(-1, 0, 0)
            elif key.char == 'd': coro = send_movement(1, 0, 0)
            elif key.char == 'q': coro = send_movement(0, 1, 0)
            elif key.char == 'e': coro = send_movement(0, -1, 0)
        except AttributeError:
            if key == keyboard.Key.esc:
                print("\nESC pressed. Closing connection...")
                if websocket_client:
                    # Schedule the close operation on the main loop and exit the listener
                    asyncio.run_coroutine_threadsafe(websocket_client.close(), loop)
                return False  # This stops the listener thread.

        if coro:
            # Safely schedule the coroutine to be executed on the main asyncio event loop
            asyncio.run_coroutine_threadsafe(coro, loop)

    # The listener runs in its own thread, so it doesn't block the main asyncio loop.
    with keyboard.Listener(on_press=on_press) as listener:
        listener.join()

if __name__ == "__main__":
    username = input("Enter your username: ")
    if create_player(username):
        main_loop = asyncio.get_event_loop()
        listener_thread = threading.Thread(target=start_keyboard_listener, args=(main_loop,), daemon=True)
        listener_thread.start()
        try:
            main_loop.run_until_complete(connect_to_game())
        except KeyboardInterrupt:
            print("\nClient stopped by user.")
        finally:
            print("Client shutdown.")
    else:
        print("Could not start client.")