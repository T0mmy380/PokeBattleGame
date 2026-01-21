import os
import time
import zipfile
import requests
from bs4 import BeautifulSoup
from selenium import webdriver
from selenium.webdriver.chrome.service import Service
from selenium.webdriver.chrome.options import Options
from selenium.webdriver.common.by import By
from selenium.webdriver.support.ui import WebDriverWait
from selenium.webdriver.support import expected_conditions as EC
from webdriver_manager.chrome import ChromeDriverManager

# --- Configuration ---
BASE_ASSET_URL = "https://spriteserver.pmdcollab.org/assets"
BATCH_SIZE = 3      # Process 5 Pokemon then rest
REST_SECONDS = 15   # Duration of rest between batches


def get_headless_browser():
    options = Options()
    options.add_argument("--headless")
    # Path to your Chrome executable
    options.binary_location = r"C:\Program Files\Google\Chrome\Application\chrome.exe" 
    options.add_argument("user-agent=Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36")
    return webdriver.Chrome(service=Service(ChromeDriverManager().install()), options=options)


def build_pmd_id(base_id, form_idx, is_shiny, is_female):
    # Builds the 4-slot ID [Base]-[Form]-[Shiny]-[Gender]
    parts = [str(base_id).zfill(4), str(form_idx).zfill(4), 
             "0001" if is_shiny else "0000", "0002" if is_female else "0000"]
    while len(parts) > 1 and parts[-1] == "0000":
        parts.pop()
    return "-".join(parts)


def download_asset(session, url, target_path, is_zip=False):
    # Handles the file writing and unzipping.
    try:
        r = session.get(url, stream=True, timeout=30)
        if r.status_code != 200: return False
        
        if is_zip:
            os.makedirs(target_path, exist_ok=True)
            temp_zip = target_path + ".tmp"
            with open(temp_zip, 'wb') as f:
                for chunk in r.iter_content(chunk_size=1024*1024): f.write(chunk)
            with zipfile.ZipFile(temp_zip, 'r') as z:
                z.extractall(target_path)
            os.remove(temp_zip)
        else:
            os.makedirs(os.path.dirname(target_path), exist_ok=True)
            with open(target_path, 'wb') as f: f.write(r.content)
        return True
    except:
        return False


def run_final_scrape(target_list):
    driver = get_headless_browser()
    session = requests.Session()
    
    # Identify the script's root directory
    script_root = os.path.dirname(os.path.abspath(__file__))
    project_root = os.path.dirname(script_root)  # Go up one level from tools/ to project root
    master_pokemon_dir = os.path.join(project_root, "assets", "characters", "pokemon")

    try:
        for index, (p_id, p_name) in enumerate(target_list):
            
            # --- BATCH BUFFER LOGIC ---
            if index > 0 and index % BATCH_SIZE == 0:
                print(f"\n--- Batch reached. Resting for {REST_SECONDS} seconds... ---")
                time.sleep(REST_SECONDS)

            print(f"\n[Processing {index + 1}/{len(target_list)}] {p_name} (ID: {p_id})...")
            driver.get(f"https://sprites.pmdcollab.org/#/{str(p_id).zfill(4)}")
            
            wait = WebDriverWait(driver, 10)
            dropdown = wait.until(EC.element_to_be_clickable((By.CSS_SELECTOR, ".MuiSelect-select")))
            
            # Scrape Credit Text
            try:
                credit_box = driver.find_element(By.XPATH, "//p[contains(text(), 'Contact')]/preceding-sibling::p")
                credits_text = credit_box.text
            except:
                credits_text = "Credits not found on page."

            dropdown.click()
            time.sleep(2)
            
            soup = BeautifulSoup(driver.page_source, 'html.parser')
            menu_items = soup.find_all('li', {'role': 'option'})
            
            form_map = {"normal": 0}
            form_counter = 0
            
            poke_folder = os.path.join(master_pokemon_dir, p_name.lower())
            os.makedirs(poke_folder, exist_ok=True)

            # Save Credits
            with open(os.path.join(poke_folder, "credits.txt"), "w", encoding="utf-8") as f:
                f.write(f"Pokemon: {p_name}\nID: {p_id}\n\n{credits_text}")

            for item in menu_items:
                label = item.find('h6').get_text(strip=True)
                clean_label = label.lower().replace(" ", "_")
                
                is_shiny = "shiny" in clean_label
                is_female = "female" in clean_label
                
                root_name = clean_label.replace("shiny", "").replace("female", "").strip("_")
                if not root_name or root_name == "normal": root_name = "normal"

                if root_name not in form_map:
                    form_counter += 1
                    form_map[root_name] = form_counter
                
                idx = form_map[root_name]
                final_id = build_pmd_id(p_id, idx, is_shiny, is_female)

                portrait_file = os.path.join(poke_folder, "portraits", f"portrait_{clean_label}.png")
                sprite_folder = os.path.join(poke_folder, "sprites", f"sprites_{clean_label}")

                print(f"  -> Building: {clean_label} (ID: {final_id})")

                if download_asset(session, f"{BASE_ASSET_URL}/portrait-{final_id}.png", portrait_file):
                    print(f"     + Portrait Saved")
                if download_asset(session, f"{BASE_ASSET_URL}/{final_id}/sprites.zip", sprite_folder, is_zip=True):
                    print(f"     + Sprites Extracted")

            # Reset dropdown for next iteration
            driver.execute_script("document.querySelector('.MuiBackdrop-root').click();")
            
    finally:
        driver.quit()
        print("\nAll tasks completed.")


if __name__ == "__main__":
    
    POKEMON_LIST = [
        (906, "Sprigatito"), 
        (909, "Fuecoco"), (912, "Quaxly"), (150, "Mewtwo"), (384, "Rayquaza"), (149, "Dragonite"), 
        (248, "Tyranitar"), (445, "Garchomp"),
    ]

    run_final_scrape(POKEMON_LIST)