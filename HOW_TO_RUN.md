# How to Run SciDAMA Project

This guide provides step-by-step instructions on how to run both the Python backend and the Flutter frontend for the SciDAMA project.

## Prerequisites
- **Python 3.x** installed
- **Flutter SDK** installed and added to your system PATH
- **Google Chrome** browser (for running the Flutter web app)

---

## 1. Running the Backend

The backend is a Python application built with FastAPI and Uvicorn. It runs locally on `http://127.0.0.1:8765`.

### Setup Dependencies (First time only)
Before running the backend for the first time, you need to install the required Python packages. Let's install them:

1. Open a terminal or Command Prompt.
2. Navigate to the `backend` directory:
   ```cmd
   cd backend
   ```
3. Install the dependencies using pip:
   ```cmd
   pip install -r requirements.txt
   ```

### Start the Server
Once the dependencies are installed, you can start the server. 

**Option A: Using the provided scripts (Recommended)**
1. Navigate back to the main project directory (`SciDAMA`).
2. Run the provided batch script:
   ```cmd
   .\run_backend.cmd
   ```
   *(Alternatively, if you are using PowerShell, you can run `.\run_backend.ps1`)*

**Option B: Manual start**
1. Ensure your terminal is in the `backend` directory.
2. Run the Uvicorn server:
   ```cmd
   python -m uvicorn main:app --host 127.0.0.1 --port 8765
   ```

If successful, you will see output indicating that the server is running. **Keep this terminal window open.**

---

## 2. Running the Flutter App in Chrome

The frontend is a Flutter application located in the `checkmath_app` directory.

1. Open a **new** terminal window (leave the backend working in the background).
2. Navigate to the Flutter app directory from the project root:
   ```cmd
   cd checkmath_app
   ```
3. Fetch the required Flutter dependencies (only needed the first time):
   ```cmd
   flutter pub get
   ```
4. Run the app, specifically targeting Chrome:
   ```cmd
   flutter run -d chrome
   ```

Chrome will automatically open and launch the application.

**Tip for Development:** If you make any changes to the Flutter code, return to this terminal window and press:
- `r` to "hot reload" (applies code changes quickly without restarting)
- `R` to "hot restart" (completely restarts the application state)

---

## 3. Playing on a Physical Mobile Device

If you are running the app on a physical phone connected to your laptop, the app will try to access the backend at `http://127.0.0.1:8765`. However, on your phone, `127.0.0.1` refers to the phone itself, not your laptop, which is why it can't reach the backend.

You have two solutions to fix this:

### Option A: Use ADB Reverse Proxy (Recommended via USB)
If your phone is plugged in via USB and you are running the app using `flutter run -d <your-device>`, you can seamlessly route the phone's localhost back to your laptop:
1. Open a terminal.
2. Run this command:
   ```cmd
   adb reverse tcp:8765 tcp:8765
   ```
3. Play the game! The default backend URL will now work perfectly.

### Option B: Use Wi-Fi Network & API Settings
If you want to play wirelessly over your local Wi-Fi network:
1. Find your laptop's local IP address (e.g., `192.168.1.5`) by running `ipconfig` in a command prompt or terminal.
2. The backend needs to listen on the entire network, not just localhost. Stop your running backend and start it with the `--network` flag:
   ```cmd
   .\run_backend.cmd --network
   ```
   *(If you get a WinError 10013, your laptop is blocking port 8765 on 0.0.0.0. You'll need to use Option A).*
3. Open the CheckMath app on your phone.
4. On the Home Screen, tap **API Settings** at the very bottom.
5. Change the URL to your laptop's IP, e.g., `http://192.168.1.5:8765` and tap **Save**.
6. Play the game!
