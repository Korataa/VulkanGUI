import shutil
import os

#define paths
scriptDir = os.path.dirname(os.path.abspath(__file__))
sourceFolder = os.path.join(os.getcwd(), "Content")
destinationFolder = os.path.join(scriptDir, "..", ".build", "x86_64-unknown-linux-gnu", "debug", "Content")

#normalize paths to avoid any issues with different OS path formats
sourceFolder = os.path.normpath(sourceFolder)
destinationFolder = os.path.normpath(destinationFolder)

#copy the content folder and its contents
try:
    shutil.copytree(sourceFolder, destinationFolder)
    print(f"successfully copied 'content' to {destinationFolder}")
except FileExistsError:
    print(f"'{destinationFolder}' already exists")
except Exception as e:
    print(f"Error occured: {e}")