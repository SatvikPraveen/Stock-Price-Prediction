import os
import subprocess
import sys

# Define the virtual environment name
ENV_NAME = "stock_env"

# Define the project structure
PROJECT_STRUCTURE = {
    "shiny_app": ["app.R"],  # RShiny app
    "notebooks": ["stock_analysis.ipynb"],  # Jupyter notebooks
    "data/raw": [],  # Raw data folder (empty)
    "data/processed": [],  # Processed data folder (empty)
    "models": [],  # Saved models
    "results": [],  # Analysis outputs
}

# Content for .gitignore
GITIGNORE_CONTENT = """__pycache__/
*.pyc
*.pyo
*.log
.env
data/*
models/*
notebooks/.ipynb_checkpoints/
.Rhistory
.RData
.Rproj.user/
.Rproj/
stock_env/
"""

# Function to create project directories and files
def create_project_structure():
    print("\n🚀 Setting up the Stock Price Prediction project structure...\n")

    for folder, files in PROJECT_STRUCTURE.items():
        os.makedirs(folder, exist_ok=True)  # Create directories
        
        for file in files:
            file_path = os.path.join(folder, file)
            if file and not os.path.exists(file_path):  # Avoid writing files in empty folders
                with open(file_path, "w") as f:
                    f.write("# " + file.replace("_", " ").title() + "\n")
                print(f"✅ Created file: {file_path}")

# Create .gitignore
if not os.path.exists(".gitignore"):
    with open(".gitignore", "w") as f:
        f.write(GITIGNORE_CONTENT)
    print("✅ Created .gitignore")

print("\n🎉 Project structure created successfully!\n")

# Function to create a virtual environment
def create_virtual_env():
    print(f"\n📦 Creating virtual environment '{ENV_NAME}'...\n")
    subprocess.run([sys.executable, "-m", "venv", ENV_NAME])

    pip_executable = os.path.join(ENV_NAME, "bin", "pip") if os.name != "nt" else os.path.join(ENV_NAME, "Scripts", "pip.exe")
    
    print("\n📦 Installing Jupyter dependencies...\n")
    subprocess.run([pip_executable, "install", "--upgrade", "pip"])
    subprocess.run([pip_executable, "install", "-r", "requirements.txt"])

    print(f"\n✅ Virtual environment '{ENV_NAME}' is ready! To activate it:\n")
    if os.name == "nt":
        print(f"   .\{ENV_NAME}\Scripts\activate")  # Windows
    else:
        print(f"   source {ENV_NAME}/bin/activate")  # Mac/Linux

# Function to install R dependencies
def install_r_dependencies():
    print("\n📦 Installing R dependencies from dependencies.R...\n")
    try:
        subprocess.run(["Rscript", "dependencies.R"], check=True)
        print("✅ R dependencies installed successfully!")
    except subprocess.CalledProcessError:
        print("❌ Error installing R dependencies. Please check dependencies.R")

if __name__ == "__main__":
    create_project_structure()
    create_virtual_env()
    install_r_dependencies()
    