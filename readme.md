# Plant Identifier Shiny App with Azure TTS (WIP)

## Description

This is a Shiny web application built with R that allows users to:
1. Upload an image of a plant.
2. Identify the plant using the PlantNet API.
3. Retrieve descriptive information about the identified plant from:
    * Plants of the World Online (POWO)
    * Plants For A Future (PFAF)
    * Wikipedia
4. Use Microsoft Azure Text-to-Speech (TTS) via Python to read the collected plant information aloud.

## Features

*   Image upload for plant identification.
*   Integration with PlantNet API.
*   Web scraping from POWO, PFAF, and Wikipedia for plant details.
*   Text-to-Speech output using Azure Cognitive Services.
*   Responsive UI built with Shiny.
*   Uses Python for Azure TTS via the `reticulate` package.
*   Audio playback using Data URIs (bypasses static file serving issues).

## Prerequisites

Before you begin, ensure you have the following installed and set up:

1.  **R:** Version 4.0 or later recommended. ([Download R](https://cran.r-project.org/))
2.  **RStudio:** Recommended IDE for R development. ([Download RStudio](https://posit.co/download/rstudio-desktop/))
3.  **Python:** Version 3.7 or later (required for `azure-cognitiveservices-speech`). Ensure Python is added to your system's PATH or that you know the path to the executable.
4.  **Git:** For cloning the repository.
5.  **PlantNet API Key:** You need to register for a free API key at [my.plantnet.org](https://my.plantnet.org/).
6.  **Microsoft Azure Account:**
    *   An active Azure subscription.
    *   A **Speech Service** resource created in your Azure portal. You will need the **Key** and **Region** for this resource.

## Setup Instructions

1.  **Clone the Repository:**
    ```bash
    git clone <your-repository-url>
    cd <repository-directory>
    ```

2.  **Install R Packages:**
    Open R or RStudio and run the following command in the console:
    ```R
    install.packages(c("shiny", "httr", "expowo", "rvest", "xml2", "reticulate", "base64enc"))
    ```

3.  **Set up Python Environment:**
    It is highly recommended to use a dedicated Python virtual environment to avoid conflicts. Choose one method:

    *   **Using Conda:**
        ```bash
        # Create a new conda environment (e.g., named 'plant_app_env')
        conda create -n plant_app_env python=3.9
        # Activate the environment
        conda activate plant_app_env
        ```

    *   **Using venv (standard Python):**
        ```bash
        # Create a virtual environment folder (e.g., named 'venv')
        python -m venv venv
        # Activate the environment
        # On Windows (cmd/powershell):
        .\venv\Scripts\activate
        # On macOS/Linux (bash/zsh):
        source venv/bin/activate
        ```

4.  **Install Python Packages:**
    With your Python environment activated (from Step 3), install the required package:
    ```bash
    pip install azure-cognitiveservices-speech
    ```

5.  **Configure API Keys and Credentials:**

    *   **PlantNet API Key:**
        *   Open the `App.R` (or `main_plant_app_with_azure_tts_SINGLE_BLOCK.R`) file.
        *   Find the `identify_plant_with_api` function.
        *   Locate the line `key <- "2b10Khs95guQFL7D7Zw0JhGPZO"` (or similar).
        *   **Replace `"2b10Khs95guQFL7D7Zw0JhGPZO"` with your actual PlantNet API key obtained from my.plantnet.org.**
        *   *Security Warning:* Do not commit your real API key to a public GitHub repository. Consider modifying the code to read this from an environment variable if sharing publicly.

    *   **Azure Speech Credentials (Environment Variables - Recommended):**
        *   The Python script `input_file_0.py` needs your Azure Speech Key and Region. It's best practice to provide these via environment variables.
        *   Set the following environment variables on your system *before* running the R script:
            *   `AZURE_SPEECH_KEY`: Your Azure Speech service key.
            *   `AZURE_SPEECH_REGION`: The region for your Azure Speech service (e.g., `uksouth`, `westus`).
        *   *(How to set environment variables varies by OS - look up persistent environment variable setting for Windows, macOS, or Linux)*.
        *   **Ensure your `input_file_0.py` script is written to read these environment variables (e.g., using `os.environ.get('AZURE_SPEECH_KEY')`).**

6.  **Configure Reticulate in R Script:**
    *   Open the `App.R` (or `main_plant_app_with_azure_tts_SINGLE_BLOCK.R`) file.
    *   Find the section `# STEP 1: EXPLICITLY CONFIGURE RETICULATE PYTHON ENVIRONMENT`.
    *   **Crucially, edit the line starting with `reticulate::use_...` to point to the Python environment you created in Step 3.**
        *   If using Conda: `reticulate::use_condaenv("plant_app_env", required = TRUE)` (Replace `"plant_app_env"` with your environment name).
        *   If using venv: `reticulate::use_virtualenv("venv", required = TRUE)` (Replace `"venv"` with your virtual environment folder name/path).
        *   If using a specific Python path: `reticulate::use_python("/path/to/your/python/executable", required = TRUE)`

7.  **Check Local Files:**
    Ensure the following files are present in the main project directory:
    *   `App.R` (or `main_plant_app_with_azure_tts_SINGLE_BLOCK.R`) - The main Shiny app script.
    *   `input_file_0.py` - The Python script containing the Azure TTS function.
    *   `scanner.mp3` - (If used) The scanner sound effect file.
    *   `www/` - Although not used for serving audio anymore, the R script might still create it for temporary storage.

## Running the App

1.  **Activate** your Python environment (Conda or venv) if it's not already active.
2.  **Ensure** your Azure environment variables (`AZURE_SPEECH_KEY`, `AZURE_SPEECH_REGION`) are set.
3.  Open RStudio and open the `App.R` (or `main_plant_app_with_azure_tts_SINGLE_BLOCK.R`) script.
4.  Click the "Run App" button in RStudio.
    *   OR: Open your system terminal, navigate to the project directory, activate the Python environment, ensure Azure variables are set, and run `Rscript App.R` (or the correct R script name).
5.  The app should launch in your default web browser.
6.  To access from another device on the same network (like your phone), ensure the `shinyApp` call at the end of the R script includes `options = list(host = "0.0.0.0")` and note the IP address and port displayed in the R console when the app starts. You may need to adjust your PC's firewall settings.

## File Structure (Key Files)
.
├── App.R # Main Shiny application script (or main_plant_app_...)
├── input_file_0.py # Python script for Azure TTS
├── scanner.mp3 # Optional scanner sound effect
├── www/ # Directory (potentially used for temporary files)
├── .gitignore # Specifies intentionally untracked files that Git should ignore
└── README.md # This file


## Dependencies

*   **R Packages:** `shiny`, `httr`, `expowo`, `rvest`, `xml2`, `reticulate`, `base64enc`
*   **Python Packages:** `azure-cognitiveservices-speech`

## Troubleshooting

*   **Reticulate/Python Issues:** Most problems arise from R not finding the correct Python environment or the `azure-cognitiveservices-speech` package. Double-check the `reticulate::use_...` line in the R script and ensure the package is installed in the *activated* environment specified there. Run `reticulate::py_config()` and `reticulate::py_module_available("azure.cognitiveservices.speech")` in the R console *after* the `reticulate::use_...` line to debug.
*   **API Key Errors:** Ensure keys/regions are correctly entered and environment variables (if used) are properly set and accessible by the R/Python processes.
*   **Network Access:** If accessing from another device fails, check the `host = "0.0.0.0"` setting in `shinyApp()` and your PC's firewall configuration.
