from flask import Flask, render_template_string, request
from scapy.all import Ether, IP, UDP, Raw, sendp
import subprocess

app = Flask(__name__)

# --- Função para montar e enviar pacote WOL ---
def wol_packet(mac, ip):
    # Normaliza MAC (remove : ou -)
    mac = mac.upper().replace(":", "").replace("-", "")
    mac_bytes = bytes.fromhex(mac)
    # Magic Packet
    magic = b"\xff" * 6 + mac_bytes * 16
    # Monta pacote UDP
    ether = Ether()
    ip_pkt = IP(dst=ip)
    udp = UDP(dport=9, sport=9)
    pkt = ether / ip_pkt / udp / Raw(load=magic)
    pkt.show2()
    # Envia
    sendp(pkt, verbose=1, count=3)


# --- Template HTML (simples) ---
html_template = """
<!DOCTYPE html>
<html>
<head>
    <title>Remote Control</title>
</head>
<body>
    <h2>Wake on LAN & Shutdown</h2>
    <form method="post">
        <label>IP do dispositivo:</label><br>
        <input type="text" name="ip" required><br><br>
        
        <label>MAC Address:</label><br>
        <input type="text" name="mac" required><br><br>
        
        <label>Usuário:</label><br>
        <input type="text" name="user"><br><br>
        
        <label>Senha:</label><br>
        <input type="password" name="password"><br><br>
        
        <button type="submit" name="action" value="wake">Wake</button>
        <button type="submit" name="action" value="shutdown">Shutdown</button>
    </form>
    <!-- <p>{{ result }}</p> -->
</body>
</html>
"""

@app.route("/", methods=["GET", "POST"])
def index():
    result = ""
    if request.method == "POST":
        ip = request.form["ip"]
        mac = request.form["mac"]
        user = request.form.get("user", "")
        password = request.form.get("password", "")
        action = request.form["action"]

        if action == "wake":
            try:
                wol_packet(mac, ip)
                result = f"WOL enviado para {mac} ({ip})"
            except Exception as e:
                result = f"Erro ao enviar WOL: {e}"

        elif action == "shutdown":
            try:
                # Monta comando net rpc
                cmd = [
                    "net", "rpc", "shutdown",
                    "-f",
                    "-t", 0,
                    "-I", ip,
                    "-U", f"IFRN\{user}%{password}"
                ]
                subprocess.run(cmd, check=True)
                result = f"Shutdown enviado para {ip}"
            except Exception as e:
                result = f"Erro no shutdown: {e}"

    return render_template_string(html_template, result=result)


if __name__ == "__main__":
    app.run(host="0.0.0.0", port=5000, debug=True)
