from selenium import webdriver
from selenium.webdriver.common.by import By
from selenium.webdriver.common.keys import Keys
from selenium.webdriver.common.action_chains import ActionChains
import time

def scrape_image_from_wallpapercave(url: str):
    # verify url
    if not url:
        return

    # Initialize the Safari WebDriver
    driver = webdriver.Safari()

    # Open a website
    driver.get(url)

    # Example: Find an element (e.g., a button) and click it
    try:
        # Find all <picture> tags and extract nested <img> tags
        picture_tags = driver.find_elements(By.TAG_NAME, "picture")
        img_urls = []
        print("Got all picture tags")

        for picture in picture_tags:
            img = picture.find_element(By.TAG_NAME, "img")
            img_urls.append(img.get_attribute("src"))
        n = len(img_urls)
        print(f"Got {n} img tags")

        # Open each image in a new tab and perform the download action
        i: int = 0
        for img_url in img_urls:
            i += 1
            # Open a new tab
            driver.execute_script("window.open('');")
            driver.switch_to.window(driver.window_handles[-1])
            
            # Open the image in the new tab
            driver.get(img_url)
            
            # Wait for the page to load
            time.sleep(1)

            # Download the image using right-click menu
            try:
                img_element = driver.find_element(By.TAG_NAME, "img")
        
                # Perform right-click on the image
                action_chains = ActionChains(driver)
                action_chains.context_click(img_element).perform()
                
                # Use JavaScript to trigger the save image command
                driver.execute_script("""
                    var img = arguments[0];
                    var link = document.createElement('a');
                    link.href = img.src;
                    link.download = '';
                    document.body.appendChild(link);
                    link.click();
                    document.body.removeChild(link);
                """, img_element)
                print(f"Image downloaded: {i} / {n}")
            except Exception as e:
                print(f"Saving image failed: {e}")
            
            # Wait for the download to start or a fixed delay
            time.sleep(1)
            
            # Close the current tab
            driver.close()
            
            # Switch back to the original tab
            driver.switch_to.window(driver.window_handles[0])

    except Exception as e:
        print(f"An error occurred: {e}")

    # Close the browser after a delay
    time.sleep(1)
    driver.quit()


def scrape_image_from_wallpaperflare(url: str):
    # verify url
    if not url:
        return

    # Initialize the Safari WebDriver
    driver = webdriver.Safari()

    # Open a website
    driver.get(url)

    # Example: Find an element (e.g., a button) and click it
    try:
        figures = driver.find_elements(By.TAG_NAME, "figure")
        img_urls = []
        print("Got all figure tags")
        print(figures)

        for figure in figures:
            img = figure.find_element(By.TAG_NAME, "a")
            print(img, img.get_attribute("href"))
            img_urls.append(img.get_attribute("href") + "/download")
        n = len(img_urls)
        print(f"Got {n} img tags")

        # Open each image in a new tab and perform the download action
        i: int = 0
        for img_url in img_urls:
            i += 1
            # Open a new tab
            driver.execute_script("window.open('');")
            driver.switch_to.window(driver.window_handles[-1])

            # Open the image in the new tab
            driver.get(img_url)

            # Wait for the page to load
            time.sleep(1)

            # Find and click the download button
            try:
                button = driver.find_element(By.ID, "dld_result")  # TODO: not working for some reason - check later
                button.click()

                print(f"Image downloaded: {i} / {n}")
            except Exception as e:
                print(f"Download button not found: {e}")

            # Wait for the download to start or a fixed delay
            time.sleep(1)
            
            # Close the current tab
            driver.close()
            
            # Switch back to the original tab
            driver.switch_to.window(driver.window_handles[0])

    except Exception as e:
        print(f"An error occurred: {e}")

    # Close the browser after a delay
    time.sleep(1)
    driver.quit()

        



    


wallpaper_urls: dict = {
    "wallpapercave": {
        "batman": "https://wallpapercave.com/batman-wallpaper",
        "harley_quinn": "https://wallpapercave.com/harley-quinn-wallpapers",
        "justice_league": "https://wallpapercave.com/justice-league-wallpaper",
        "avengers": "https://wallpapercave.com/avengers-wallpaper-hd",
        "marvel": "https://wallpapercave.com/marvel-wallpapers",
        "avengers2": "https://wallpapercave.com/the-avenger-wallpaper-hd",
    },
    "wallpaperflare": {
        "batman": "https://www.wallpaperflare.com/search?wallpaper=Batman"
    }
}
scrape_image_from_wallpapercave(wallpaper_urls["wallpapercave"]["avengers2"])
# scrape_image_from_wallpaperflare(wallpaper_urls["wallpaperflare"]["batman"])