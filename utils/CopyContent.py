import shutil
import os

#define paths
scriptDir = os.path.dirname(os.path.abspath(__file__))
sourceFolder = os.path.join(os.getcwd(), "Assets")
destinationFolder = os.path.join(scriptDir, "..", ".build", "x86_64-unknown-linux-gnu", "debug", "Assets")

#normalize paths to avoid any issues with different OS path formats
sourceFolder = os.path.normpath(sourceFolder)
destinationFolder = os.path.normpath(destinationFolder)

#remove existing destination folder if it exists
if os.path.exists(destinationFolder):
    print(f"Removing existing folder: {destinationFolder}")
    shutil.rmtree(destinationFolder)

#copy the content folder and its contents
try:
    shutil.copytree(sourceFolder, destinationFolder)
    print(f"successfully copied 'assets' to {destinationFolder}")
except Exception as e:
    print(f"Error occurred: {e}")