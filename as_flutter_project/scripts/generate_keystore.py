#!/usr/bin/env python3
"""
Generate Android signing keystore for Flutter release builds.
This script creates a keystore file used to sign APK releases.
"""

import subprocess
import sys
import os
from pathlib import Path

def generate_keystore():
    """Generate Android release keystore using keytool"""
    
    # Configuration
    keystore_dir = Path("c:\\keys")
    keystore_path = keystore_dir / "release-key.jks"
    store_password = "AstralMinds2024!"
    key_password = "AstralMinds2024!"
    key_alias = "release"
    validity = "10000"  # days
    dname = "CN=AstralMinds, OU=Development, O=AstralMinds, L=Manila, ST=Metro Manila, C=PH"
    
    # Create directory if it doesn't exist
    keystore_dir.mkdir(parents=True, exist_ok=True)
    
    # Check if keystore already exists
    if keystore_path.exists():
        print(f"✅ Keystore already exists at: {keystore_path}")
        return True
    
    print("🔑 Generating Android signing keystore...")
    print(f"📁 Keystore path: {keystore_path}")
    
    # Try to find keytool
    java_home = os.environ.get('JAVA_HOME')
    if java_home:
        keytool_path = Path(java_home) / "bin" / "keytool"
    else:
        keytool_path = Path("keytool")  # Will search in PATH
    
    # Build keytool command
    cmd = [
        str(keytool_path),
        "-genkey",
        "-v",
        "-keystore", str(keystore_path),
        "-keyalg", "RSA",
        "-keysize", "2048",
        "-validity", validity,
        "-alias", key_alias,
        "-storepass", store_password,
        "-keypass", key_password,
        "-dname", dname,
    ]
    
    try:
        print(f"▶️ Running: {' '.join(cmd[:3])} ...")
        result = subprocess.run(cmd, check=True, capture_output=True, text=True)
        print(result.stdout)
        print("✅ Keystore generated successfully!")
        return True
    except FileNotFoundError:
        print("❌ keytool not found. Make sure Java is installed and JAVA_HOME is set.")
        print("\n📝 Manual setup instructions:")
        print("1. Install Java JDK (includes keytool)")
        print("2. Set JAVA_HOME environment variable")
        print("3. Run this script again")
        return False
    except subprocess.CalledProcessError as e:
        print(f"❌ Error generating keystore: {e.stderr}")
        return False

if __name__ == "__main__":
    success = generate_keystore()
    sys.exit(0 if success else 1)
