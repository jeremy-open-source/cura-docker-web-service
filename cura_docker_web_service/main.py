import asyncio

from fastapi import FastAPI, UploadFile, File, BackgroundTasks
from fastapi.responses import HTMLResponse
from fastapi.staticfiles import StaticFiles
from fastapi.templating import Jinja2Templates
import subprocess
import os
import socket
from datetime import datetime

root_dir = os.path.realpath(os.path.dirname(os.path.realpath(__file__)) + "/..")

# Environment variables for directory paths
STL_DIR = os.getenv("STL_DIR", "/opt/stl-files")
RESOLUTION_X = os.getenv("RESOLUTION_X", "1920")
RESOLUTION_Y = os.getenv("RESOLUTION_Y", "1080")
NOVNC_DIR = os.getenv("NOVNC_DIR")
START_PORT = 5901


app = FastAPI()

# Setup templates and static file directories
app.mount("/novnc", StaticFiles(directory=NOVNC_DIR), name="novnc")
templates = Jinja2Templates(directory=f"{root_dir}/templates")

class CuraInstance:
    def __init__(
        self,
        rdp_port: int,
        display: str,
        xvfb_process: subprocess.Popen,
        openbox_process: subprocess.Popen,
        x11vnc_process: subprocess.Popen,
        cura_process: subprocess.Popen
    ):
        self.rdp_port = rdp_port
        self.display = display
        self.xvfb_process = xvfb_process
        self.openbox_process = openbox_process
        self.x11vnc_process = x11vnc_process
        self.cura_process = cura_process

    async def terminate_processes(self):
        for proc in [self.xvfb_process, self.openbox_process, self.x11vnc_process, self.cura_process]:
            proc.terminate()  # Send SIGTERM
            try:
                proc.wait(timeout=3)  # Wait for the process to terminate
            except subprocess.TimeoutExpired:
                proc.kill()  # Force kill if necessary

    @staticmethod
    async def start(rdp_port: int, file_path: str | None = None):
        display = f":{rdp_port - 5900}"
        process_envs = {
            **os.environ.copy(),
            **{
                "DISPLAY": display,
            }
        }

        xvfb_process = subprocess.Popen([
            "Xvfb",
            display,
            "-screen",
            "0",
            f"{RESOLUTION_X}x{RESOLUTION_Y}x24"],
            env=process_envs,
        )
        openbox_process = subprocess.Popen(["openbox"], env=process_envs)
        x11vnc_process = subprocess.Popen([
            "x11vnc",
            "-ncache",
            "10",
            "-display",
            display,
            "-forever",
            "-shared",
            "-rfbport",
            str(rdp_port),
        ], env=process_envs)

        cura_cmd = ["/opt/cura/extracted/AppRun", "-geometry", f"{RESOLUTION_X}x{RESOLUTION_Y}+0+0"]
        if file_path:
            cura_cmd.append(file_path)

        cura_process = subprocess.Popen(cura_cmd, env=process_envs)

        return CuraInstance(
            rdp_port,
            display,
            xvfb_process,
            openbox_process,
            x11vnc_process,
            cura_process,
        )

class CuraInstances:
    def __init__(self):
        self.instances: dict[int, CuraInstance | None] = {}
        self.lock = asyncio.Lock()

    async def allocate_port(self) -> int:
        async with self.lock:
            use_port = START_PORT
            while use_port in self.instances:
                use_port += 1
            self.instances[use_port] = None
        return use_port

    async def start_instance(self, port: int, file_path: str | None = None):
        if port not in self.instances:
            raise ValueError(f"Port {port} has not been allocated")
        if self.instances[port] is not None:
            raise ValueError(f"Port {port} is already started")
        self.instances[port] = await CuraInstance.start(port, file_path)

    async def get_instance(self, port: int) -> CuraInstance:
        if port not in self.instances:
            raise ValueError(f"Port {port} not set")
        if self.instances[port] is None:
            raise ValueError(f"Port {port} has not been started")
        return self.instances[port]

    async def get_open_ports(self) -> list[int]:
        return list(self.instances.keys())

    async def terminate_instance(self, port: int) -> None:
        instance = await self.get_instance(port)
        await instance.terminate_processes()
        del self.instances[port]

cura_instances = CuraInstances()

async def start_cura(port: int, file_path: str = None):
    await cura_instances.start_instance(port, file_path)

async def close_cura(port: int):
    await cura_instances.terminate_instance(port)

@app.get("/", response_class=HTMLResponse)
async def read_root():
    hostname = socket.gethostname()
    return templates.TemplateResponse(
        "index.html",
        {
            "request": {},
            "hostname": hostname,
            "resolution_x": RESOLUTION_X,
            "resolution_y": RESOLUTION_Y,
        }
    )

@app.post("/upload")
async def upload_file(file: UploadFile = File(...), background_tasks: BackgroundTasks = BackgroundTasks()):
    current_date = datetime.now().strftime("%Y%m%d")
    original_filename = file.filename
    new_filename = f"{current_date}-{original_filename}"
    file_path = os.path.join(STL_DIR, new_filename)
    with open(file_path, "wb+") as f:
        f.write(await file.read())
    port = await cura_instances.allocate_port()
    background_tasks.add_task(start_cura, port, file_path)
    return {"port": port}

@app.post("/open_cura")
async def open_cura(background_tasks: BackgroundTasks):
    port = await cura_instances.allocate_port()
    background_tasks.add_task(start_cura, port, None)
    return {"port": port}

@app.get("/get_open_ports")
async def get_open_ports():
    ports = (await cura_instances.get_open_ports())
    # ports.sort()
    return {"ports": ports}

@app.post("/close_instance/{port}")
async def close_instance(port: int, background_tasks: BackgroundTasks):
    background_tasks.add_task(close_cura, port)
    return {}, 204

if __name__ == "__main__":
    import uvicorn
    uvicorn.run(app, host="0.0.0.0", port=8000)
