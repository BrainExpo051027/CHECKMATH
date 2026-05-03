import asyncio
import websockets
import json

async def test():
    # Connect host
    host_ws = await websockets.connect("ws://127.0.0.1:8765/ws/matchmaking/9999?name=MobileHost&role=host")
    msg1 = await host_ws.recv()
    print("Host joined:", msg1)

    # Connect guest
    guest_ws = await websockets.connect("ws://127.0.0.1:8765/ws/matchmaking/9999?name=LaptopGuest&role=guest")
    msg2 = await guest_ws.recv()
    print("Guest joined:", msg2)

    # Check host for opponent_joined
    msg3 = await host_ws.recv()
    print("Host received:", msg3)

    await host_ws.close()
    await guest_ws.close()

if __name__ == "__main__":
    asyncio.run(test())
