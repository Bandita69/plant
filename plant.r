# main_plant_app_with_azure_tts_SINGLE_BLOCK.R

# ---------------------------------------------------------------------------
# Load Libraries
# ---------------------------------------------------------------------------
library(shiny)
library(httr)
library(expowo)
library(rvest)
library(xml2)
library(reticulate)
library(base64enc) # Added for Data URI method

# ---------------------------------------------------------------------------
# STEP 1: EXPLICITLY CONFIGURE RETICULATE PYTHON ENVIRONMENT
# ---------------------------------------------------------------------------
reticulate::use_condaenv("base", required = TRUE)

# ---------------------------------------------------------------------------
# STEP 2: DEFINE PYTHON SCRIPT PATH AND SOURCE IT
# ---------------------------------------------------------------------------
PYTHON_SCRIPT_NAME <- "input_file_0.py"

if (!file.exists(PYTHON_SCRIPT_NAME)) {
  stop(paste0("Python script '", PYTHON_SCRIPT_NAME, "' not found in the app directory. ",
              "Please ensure it's there and contains 'synthesize_speech_to_file' function."))
}

tryCatch({
  source_python(PYTHON_SCRIPT_NAME)
  print(paste0("Python script '", PYTHON_SCRIPT_NAME, "' loaded successfully."))
  if (!exists("synthesize_speech_to_file") || !is.function(synthesize_speech_to_file)) {
      stop(paste0("Function 'synthesize_speech_to_file' not found or not a function after sourcing '", PYTHON_SCRIPT_NAME, "'."))
  }
}, error = function(e) {
  print(paste0("Error loading Python script '", PYTHON_SCRIPT_NAME, "': ", e$message))
  py_err <- reticulate::py_last_error()
  if(!is.null(py_err)) { print("Python error details:"); print(py_err) }
  stop(paste0("Could not load Python script. Ensure reticulate is configured correctly (use_condaenv, etc. *before* this step) ",
              "and 'azure.cognitiveservices.speech' is installed in the chosen Python environment."))
})

# --- Plant Identification & Data Fetching Functions (Keep as they are) ---
identify_plant_with_api <- function(image_path, organ_choice) {
  API_URL <- "https://my-api.plantnet.org/v2/identify"
  key <- "YOUR_PLANTNET_API_KEY"
  project <- "all"
  lang <- "en"
  includeRelatedImages <- FALSE
  URL <- paste0(API_URL, "/", project, "?", "lang=", lang, "&include-related-images=", includeRelatedImages, "&api-key=", key)
  if (!file.exists(image_path)) {
    return(list(error = paste("Image file not found at:", image_path)))
  }
  data_for_api <- list("images" = httr::upload_file(image_path), "organs" = organ_choice)
  response_api <- NULL
  tryCatch({
    response_api <- httr::POST(URL, body = data_for_api, encode = "multipart", httr::timeout(30))
  }, error = function(e) {
    return(list(error = paste("PlantNet API: Network error - ", e$message)))
  })
  if(is.null(response_api)) return(list(error = "PlantNet API: No response from server (timeout or network issue)."))
  status_api <- httr::status_code(response_api)
  if (status_api == 200) {
    result_api <- httr::content(response_api, as = "parsed", type = "application/json")
    if (!is.null(result_api$results) && length(result_api$results) > 0 &&
        !is.null(result_api$results[[1]]$species) &&
        !is.null(result_api$results[[1]]$species$scientificNameWithoutAuthor) &&
        !is.null(result_api$results[[1]]$species$family) &&
        !is.null(result_api$results[[1]]$species$family$scientificNameWithoutAuthor)) {
      best_match <- result_api$results[[1]]
      return(list(
        species_for_powo = best_match$species$scientificName,
        species_for_pfaf_wiki = best_match$species$scientificNameWithoutAuthor,
        family = best_match$species$family$scientificNameWithoutAuthor,
        score = best_match$score,
        common_names = paste(best_match$species$commonNames, collapse=", "),
        full_scientific_name_display = best_match$species$scientificName,
        error = NULL
      ))
    } else {
      return(list(error = "PlantNet API: No identification results or unexpected structure in response."))
    }
  } else {
    error_content <- httr::content(response_api, as = "text", encoding = "UTF-8")
    return(list(error = paste("PlantNet API request failed. Status:", status_api, "Response:", substr(error_content, 1, 200))))
  }
}

fetch_powo_description <- function(target_family, species_for_powo) {
  if (is.null(species_for_powo) || is.null(target_family) || species_for_powo == "" || target_family == "") {
    return(list(description = NULL, error = "POWO: Missing family or species for lookup."))
  }
  plant_info_powo <- NULL
  tryCatch({
    plant_info_powo <- powoSpDist(family = target_family, species = species_for_powo, save = FALSE, verbose = FALSE)
  }, error = function(e) {
    return(list(description = NULL, error = paste("POWO: expowo::powoSpDist error -", e$message)))
  })
  if(!is.null(plant_info_powo$error) && inherits(plant_info_powo, "list")) return(plant_info_powo)
  if (!is.null(plant_info_powo) && nrow(plant_info_powo) > 0 && "powo_uri" %in% names(plant_info_powo)) {
    base_powo_url <- plant_info_powo$powo_uri[1]
    description_url_powo <- paste0(base_powo_url, "/general-information")
    response_powo <- NULL
    tryCatch({
        response_powo <- GET(description_url_powo,
                            user_agent("Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/100.0.0.0 Safari/537.36"),
                            httr::timeout(15))
    }, error = function(e) {
        return(list(description = NULL, error = paste("POWO: Network error fetching description page -", e$message)))
    })
    if(is.null(response_powo)) return(list(description = NULL, error = "POWO: No response from description server."))
    if (status_code(response_powo) == 200) {
      page_html_powo <- content(response_powo, as = "parsed", encoding = "UTF-8")
      found_heading_text <- NULL
      possible_heading_texts <- c("General Description", "General Information", "Description")
      for(heading_text_candidate in possible_heading_texts){
          xpath_test_heading <- paste0("//*[normalize-space(.)='", heading_text_candidate, "']")
          found_test_elements <- html_elements(page_html_powo, xpath = xpath_test_heading)
          if(length(found_test_elements) > 0){
              found_heading_text <- heading_text_candidate
              break
          }
      }
      description_paragraphs <- NULL
      if(is.null(found_heading_text)){
          dt_elements <- html_elements(page_html_powo, xpath = "//dl[contains(@class, 'powo-details')]//dt")
          dd_elements <- html_elements(page_html_powo, xpath = "//dl[contains(@class, 'powo-details')]//dd")
          if (length(dt_elements) > 0 && length(dd_elements) >= length(dt_elements)) {
             first_desc_p <- html_elements(dd_elements[1], xpath=".//p")
             if(length(first_desc_p)>0) {
                description_paragraphs <- first_desc_p
             } else {
                return(list(description = NULL, error = "POWO: Could not find known description heading or fallback dt/dd paragraphs on page."))
             }
          } else {
            return(list(description = NULL, error = "POWO: Could not find description heading on page and no fallback dt/dd structure found."))
          }
      } else {
        xpath_full_selector <- paste0("//dt[span[normalize-space(.)='", found_heading_text, "']]/following-sibling::dd[1]//p")
        description_paragraphs <- html_elements(page_html_powo, xpath = xpath_full_selector)
      }

      if (!is.null(description_paragraphs) && length(description_paragraphs) > 0) {
        description_text_vector <- html_text(description_paragraphs)
        full_description_combined <- paste(description_text_vector, collapse = " ")
        full_description_combined <- gsub("\u00A0", " ", full_description_combined)
        full_description_combined <- gsub("\\s+", " ", trimws(full_description_combined))
        return(list(description = full_description_combined, error = NULL))
      } else {
        return(list(description = NULL, error = "POWO: No description paragraphs found under heading or in fallback."))
      }
    } else {
      return(list(description = NULL, error = paste("POWO: Failed to fetch page. Status:", status_code(response_powo))))
    }
  } else {
    err_msg <- paste("POWO: Could not get POWO URI for Family:", target_family, "Species:", species_for_powo)
    if (!is.null(plant_info_powo) && inherits(plant_info_powo, "data.frame") && nrow(plant_info_powo) == 0) {
      err_msg <- paste(err_msg, "expowo returned 0 rows (species not found or data missing).")
    } else if (is.null(plant_info_powo)){
      err_msg <- paste(err_msg, "expowo call failed or returned NULL.")
    }
    return(list(description = NULL, error = err_msg))
  }
}

fetch_pfaf_details <- function(species_for_pfaf) {
  if (is.null(species_for_pfaf) || species_for_pfaf == "") {
    return(list(hazards = NULL, other_uses_sentence = NULL, medicinal_uses_sentences = NULL, error = "PFAF: Missing Latin name for lookup."))
  }
  formatted_latin_name <- gsub(" ", "+", species_for_pfaf)
  pfaf_url <- paste0("https://pfaf.org/user/Plant.aspx?LatinName=", formatted_latin_name)
  response_pfaf <- NULL
  tryCatch({
    response_pfaf <- GET(pfaf_url,
                         user_agent("Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/100.0.0.0 Safari/537.36"),
                         httr::timeout(15))
  }, error = function(e) {
    return(list(hazards = NULL, other_uses_sentence = NULL, medicinal_uses_sentences = NULL, error = paste("PFAF: Network error -", e$message)))
  })
  if(is.null(response_pfaf)) return(list(hazards = NULL, other_uses_sentence = NULL, medicinal_uses_sentences = NULL, error = "PFAF: No response from server."))
  if (status_code(response_pfaf) != 200) {
    return(list(hazards = NULL, other_uses_sentence = NULL, medicinal_uses_sentences = NULL, error = paste("PFAF: Failed to fetch page. Status:", status_code(response_pfaf))))
  }
  page_html_pfaf <- content(response_pfaf, as = "parsed", encoding = "UTF-8")
  hazards_text <- NULL
  other_uses_sentence <- NULL
  medicinal_uses_sentences <- NULL
  tryCatch({
    hazards_node <- html_element(page_html_pfaf, xpath = "//span[@id='ContentPlaceHolder1_lblKnownHazards']")
    if (!is.na(hazards_node)) {
      hazards_text_raw <- trimws(html_text(hazards_node))
      hazards_text <- if (tolower(hazards_text_raw) != "none known") hazards_text_raw else "None known"
    }
  }, error = function(e) { message(paste("PFAF: Error parsing hazards -", e$message))})
  tryCatch({
    other_uses_node <- html_element(page_html_pfaf, xpath = "//span[@id='ContentPlaceHolder1_txtOtherUses']")
    if(!is.na(other_uses_node)) {
      other_uses_html_string <- as.character(other_uses_node)
      match_info <- gregexpr("<br\\s*/?>\\s*<br\\s*/?>", other_uses_html_string, ignore.case = TRUE, perl=TRUE)
      start_of_main_text_html <- ""
      if (length(match_info[[1]]) > 0 && match_info[[1]][1] != -1) {
          last_br_br_end_pos <- match_info[[1]][length(match_info[[1]])] + attr(match_info[[1]], "match.length")[length(match_info[[1]])]
          if (last_br_br_end_pos <= nchar(other_uses_html_string)) {
              start_of_main_text_html <- substr(other_uses_html_string, last_br_br_end_pos, nchar(other_uses_html_string))
          }
      } else {
           links_removed_html <- gsub("<a[^>]*>.*?</a>", "", other_uses_html_string, ignore.case = TRUE)
           links_removed_html <- gsub("<br\\s*/?>", " ", links_removed_html, ignore.case = TRUE)
           start_of_main_text_html <- links_removed_html
      }
      if (nchar(start_of_main_text_html) > 0) {
          main_text_plain <- html_text(read_html(paste0("<div>", start_of_main_text_html, "</div>")), trim = TRUE)
          main_text_plain <- gsub("\\s+", " ", main_text_plain)
          if (nchar(main_text_plain) > 0) {
              sentences <- unlist(strsplit(main_text_plain, "(?<=[.?!])\\s+", perl = TRUE))
              if(length(sentences) > 0) {
                  other_uses_sentence <- trimws(sentences[1])
              }
          }
      }
    }
  }, error = function(e) { message(paste("PFAF: Error parsing Other Uses (refined) -", e$message))})
  tryCatch({
    medicinal_uses_node <- html_element(page_html_pfaf, xpath = "//span[@id='ContentPlaceHolder1_txtMediUses']")
    if(!is.na(medicinal_uses_node)){
      medicinal_uses_html_string <- as.character(medicinal_uses_node)
      medicinal_uses_html_string <- sub("^\\s*<i>.*?</i>\\s*<br\\s*/?>", "", medicinal_uses_html_string, ignore.case = TRUE, perl=TRUE)
      match_info_med <- gregexpr("<br\\s*/?>\\s*<br\\s*/?>", medicinal_uses_html_string, ignore.case = TRUE, perl=TRUE)
      start_of_main_text_html_med <- ""
      if (length(match_info_med[[1]]) > 0 && match_info_med[[1]][1] != -1) {
          last_br_br_med_end_pos <- match_info_med[[1]][length(match_info_med[[1]])] + attr(match_info_med[[1]], "match.length")[length(match_info_med[[1]])]
          if (last_br_br_med_end_pos <= nchar(medicinal_uses_html_string)) {
              start_of_main_text_html_med <- substr(medicinal_uses_html_string, last_br_br_med_end_pos, nchar(medicinal_uses_html_string))
          }
      } else {
           links_removed_html_med <- gsub("<a[^>]*>.*?</a>", "", medicinal_uses_html_string, ignore.case = TRUE)
           links_removed_html_med <- gsub("<br\\s*/?>", " ", links_removed_html_med, ignore.case = TRUE)
           start_of_main_text_html_med <- links_removed_html_med
      }
      if (nchar(start_of_main_text_html_med) > 0) {
          main_text_plain_med <- html_text(read_html(paste0("<div>", start_of_main_text_html_med, "</div>")), trim = TRUE)
          main_text_plain_med <- sub("Chemical Constituents:.*$", "", main_text_plain_med)
          main_text_plain_med <- gsub("\\s+", " ", trimws(main_text_plain_med))
          if (nchar(main_text_plain_med) > 0) {
              sentences_med <- unlist(strsplit(main_text_plain_med, "(?<=[.?!])\\s+", perl = TRUE))
              if(length(sentences_med) >= 2) {
                  medicinal_uses_sentences <- paste(trimws(sentences_med[1]), trimws(sentences_med[2]))
              } else if (length(sentences_med) == 1) {
                  medicinal_uses_sentences <- trimws(sentences_med[1])
              }
          }
      }
    }
  }, error = function(e) { message(paste("PFAF: Error parsing Medicinal Uses (refined) -", e$message))})
  return(list(hazards = hazards_text, other_uses_sentence = other_uses_sentence, medicinal_uses_sentences = medicinal_uses_sentences, error = NULL))
}

fetch_wikipedia_details <- function(species_for_wiki) {
  if (is.null(species_for_wiki) || species_for_wiki == "") {
    return(list(etymology = NULL, intro = NULL, error = "Wikipedia: Missing Latin name for lookup."))
  }
  formatted_latin_name <- gsub(" ", "_", species_for_wiki)
  wiki_url <- paste0("https://en.wikipedia.org/wiki/", formatted_latin_name)
  response_wiki <- NULL
  tryCatch({
    response_wiki <- GET(wiki_url, user_agent("Mozilla/5.0 (compatible; MyShinyAppPlantInfo/1.0; +http://example.com/bot)"), httr::timeout(15))
  }, error = function(e) {
    return(list(etymology = NULL, intro = NULL, error = paste("Wikipedia: Network error -", e$message)))
  })
  if(is.null(response_wiki)) return(list(etymology = NULL, intro = NULL, error = "Wikipedia: No response from server."))
  if (status_code(response_wiki) != 200) {
    if (status_code(response_wiki) == 404 && grepl(" ", species_for_wiki)) {
        generic_species_name <- sub("^(\\w+\\s+\\w+).*", "\\1", species_for_wiki)
        if (generic_species_name != species_for_wiki) {
            message(paste("Wikipedia: 404 for", species_for_wiki, "Trying generic species:", generic_species_name))
            return(fetch_wikipedia_details(generic_species_name))
        }
    }
    return(list(etymology = NULL, intro = NULL, error = paste("Wikipedia: Failed to fetch page. Status:", status_code(response_wiki))))
  }
  page_html_wiki <- content(response_wiki, as = "parsed", encoding = "UTF-8")
  etymology_sentences <- NULL
  intro_sentences <- NULL
  process_wiki_paragraphs <- function(paragraph_nodes) {
    if(length(paragraph_nodes) > 0) {
        all_text <- paste(sapply(paragraph_nodes, function(p) {
                                  xml_remove(xml_find_all(p, ".//sup"))
                                  text <- html_text(p, trim=TRUE)
                                  text <- gsub("\\[\\d+(?:,\\s*\\d+)*\\]", "", text)
                                  text <- gsub("\\[edit\\]", "", text, ignore.case = TRUE)
                                  return(text)
                                }), collapse=" ")
        all_text <- gsub("\\s+", " ", trimws(all_text))
        sentences <- unlist(strsplit(all_text, "(?<=[.?!])\\s+(?=[A-ZΑ-ΩΆ-Ώ])", perl = TRUE))
        sentences <- trimws(sentences)
        sentences <- sentences[nchar(sentences) > 5]
        if(length(sentences) >= 2) {
            return(paste(sentences[1], sentences[2]))
        } else if (length(sentences) == 1) {
            return(sentences[1])
        }
    }
    return(NULL)
  }
  tryCatch({
    etymology_heading_node <- html_element(page_html_wiki, xpath = "//h2[@id='Etymology' or .//span[@id='Etymology' or normalize-space(text())='Etymology']]")
    if(!is.na(etymology_heading_node)){
      etymology_paragraphs_nodes <- html_elements(etymology_heading_node,
          xpath = "following-sibling::p[count(preceding-sibling::h2[1]) = count(preceding-sibling::h2[. = current()]))]")
      if(length(etymology_paragraphs_nodes) == 0) {
         etymology_paragraphs_nodes <- html_elements(page_html_wiki, xpath = "//h2[@id='Etymology' or .//span[@id='Etymology' or normalize-space(text())='Etymology']]/following-sibling::p[1]")
         if(length(html_elements(etymology_paragraphs_nodes[1], xpath="following-sibling::p[1]")) > 0 && length(etymology_paragraphs_nodes) ==1) {
            etymology_paragraphs_nodes <- c(etymology_paragraphs_nodes, html_elements(etymology_paragraphs_nodes[1], xpath="following-sibling::p[1]"))
         }
      }
      etymology_sentences <- process_wiki_paragraphs(etymology_paragraphs_nodes)
    }
  }, error = function(e) { message(paste("Wikipedia: Error parsing Etymology -", e$message))})
  if (is.null(etymology_sentences) || nchar(etymology_sentences) < 20 ) {
    tryCatch({
      intro_p_nodes <- html_elements(page_html_wiki, xpath = "(//div[@id='mw-content-text']/div[contains(@class,'mw-parser-output')]/p[not(ancestor::table) and not(ancestor::div[contains(@class,'infobox')]) and string-length(normalize-space(.)) > 50])[position() <= 2]")
      intro_sentences <- process_wiki_paragraphs(intro_p_nodes)
    }, error = function(e) { message(paste("Wikipedia: Error parsing Intro -", e$message))})
  }
  return(list(etymology = etymology_sentences, intro = intro_sentences, error = NULL))
}

# --- Shiny UI ---
ui <- fluidPage(
  titlePanel("Plant Identifier & Info Finder with Azure TTS (Simple)"),
  tags$head(
    tags$style(HTML('
      body {
        background-image: url("https://i.ibb.co/ZfpYLyW/Adobe-Stock-563241534.jpg");
        background-size: cover;
        background-repeat: no-repeat;
        background-position: center center;
        background-attachment: fixed;
      }
      .well { background-color: rgba(255, 255, 255, 0.85); }
      .shiny-output-error-validation { color: red; font-weight: bold; }
      #ttsAudioContainer audio { width: 100%; margin-top: 5px; display: block; }
      #ttsStatus { margin-top: 10px; font-style: italic; color: #555; }
      #scannerAudioElement { display: none; }
    ')),
    tags$audio(id = "scannerAudioElement", preload = "auto",
               tags$source(src = "scanner.mp3", type = "audio/mpeg"),
               "Your browser does not support the audio element."
    )
  ),
  sidebarLayout(
    sidebarPanel(
      fileInput("image_upload", "Upload Plant Image (JPG or PNG)", accept = c("image/jpeg", "image/png")),
      selectInput("organ_type", "Organ Type (PlantNet):", choices = list("Auto" = "auto", "Leaf" = "leaf", "Flower" = "flower", "Fruit" = "fruit", "Bark" = "bark"), selected = "auto"),
      actionButton("identify_btn", "Identify Plant & Get Info"),
      hr(),
      h4("Text-to-Speech (Azure):"),
      selectInput("azure_voice_select", "Select Azure Voice:",
                  choices = list(
                      "UK - Libby (Female Neural)" = "en-GB-LibbyNeural",
                      "Ireland - Emily (Female Neural)" = "en-IE-EmilyNeural"
                  ),
                  selected = "en-GB-LibbyNeural"),
      actionButton("read_aloud_btn", "Read Information Aloud", icon = icon("volume-up")),
      div(id = "ttsStatus", "TTS: Ready."),
      div(id = "ttsAudioContainer", style = "margin-top: 15px;"),
      hr(),
      p("Note: Uses PlantNet API, POWO, PFAF, Wikipedia. TTS by Azure (via Python).")
    ),
    mainPanel(
      h4("Uploaded Image:"),
      imageOutput("uploaded_image_display", height = "300px"),
      hr(),
      h4("Identification Result:"),
      uiOutput("identification_status"),
      strong("Scientific Name:"), textOutput("plant_scientific_name"),
      strong("Common Names:"), textOutput("plant_common_names"),
      strong("Family:"), textOutput("plant_family"),
      strong("PlantNet Score:"), textOutput("plantnet_score"),
      hr(),
      h4("Information from Data Sources:"),
      uiOutput("description_status"),
      htmlOutput("plant_info_combined")
    )
  ),
  tags$script(HTML(
  "
  let currentSingleAudioPlayer = null;

  Shiny.addCustomMessageHandler('playSingleAzureAudio', function(message) {
    const audioDataUri = message.data_uri; // Use data_uri
    const ttsAudioContainer = document.getElementById('ttsAudioContainer');
    const ttsStatus = document.getElementById('ttsStatus');

    if (currentSingleAudioPlayer) {
      currentSingleAudioPlayer.pause();
      currentSingleAudioPlayer.removeEventListener('ended', singleAudioEnded);
      currentSingleAudioPlayer.removeEventListener('error', singleAudioError);
    }

    ttsAudioContainer.innerHTML = ''; // Clear previous player

    if (!audioDataUri) { // Check data_uri
        ttsStatus.textContent = 'TTS: No audio data URI received.';
        $('#read_aloud_btn').prop('disabled', false).text('Read Information Aloud');
        return;
    }

    currentSingleAudioPlayer = document.createElement('audio');
    currentSingleAudioPlayer.controls = true;
    currentSingleAudioPlayer.src = audioDataUri; // Set src to data_uri

    currentSingleAudioPlayer.addEventListener('ended', singleAudioEnded);
    currentSingleAudioPlayer.addEventListener('error', singleAudioError);

    ttsAudioContainer.appendChild(currentSingleAudioPlayer);
    ttsStatus.textContent = 'TTS: Playing audio...';
    $('#read_aloud_btn').prop('disabled', true).text('Reading...');

    currentSingleAudioPlayer.play().catch(error => {
      console.error('Error playing single Azure audio from Data URI:', error); // Updated log
      ttsStatus.textContent = `TTS: Error playing audio. ${error.message}.`;
      $('#read_aloud_btn').prop('disabled', false).text('Read Information Aloud');
    });
  });

  function singleAudioEnded() {
    $('#ttsStatus').text('TTS: Finished speaking.');
    $('#read_aloud_btn').prop('disabled', false).text('Read Information Aloud');
  }

  function singleAudioError(event) {
    console.error('Single audio element error occurred playing Data URI:', event); // Updated log
    $('#ttsStatus').text('TTS: Error playing audio. Skipping.');
    $('#read_aloud_btn').prop('disabled', false).text('Read Information Aloud');
  }

  Shiny.addCustomMessageHandler('updateTTSStatus', function(message) {
    $('#ttsStatus').text('TTS: ' + message.status);
    if (typeof message.enableButton !== 'undefined') {
        $('#read_aloud_btn').prop('disabled', !message.enableButton).text(message.enableButton ? 'Read Information Aloud' : 'Reading...');
    }
  });

  const scannerAudio = document.getElementById('scannerAudioElement');
  let hasScannerPlayedThisCycle = false;
  Shiny.addCustomMessageHandler('playScannerSound', function(message) {
    if (scannerAudio && !hasScannerPlayedThisCycle) {
      hasScannerPlayedThisCycle = true;
      console.log('Scanner: Attempting to play one-shot sound.');
      scannerAudio.currentTime = 0;
      const playPromise = scannerAudio.play();
      if (playPromise !== undefined) {
        playPromise.then(() => {
          console.log('Scanner: Playback initiated successfully.');
        }).catch((error) => {
          console.warn('Scanner: Playback failed or was prevented.', error);
        });
      }
    } else if (scannerAudio && hasScannerPlayedThisCycle) {
      console.log('Scanner: Play already attempted for this identification cycle.');
    } else if (!scannerAudio) {
      console.error('Scanner: Audio element #scannerAudioElement not found!');
    }
  });
  Shiny.addCustomMessageHandler('stopScannerSound', function(message) {
    console.log('Scanner: Stop signal received (processing finished).');
    hasScannerPlayedThisCycle = false;
  });
  "
  ))
)

# --- Shiny Server ---
server <- function(input, output, session) {

    app_dir <- tryCatch(dirname(rstudioapi::getSourceEditorContext()$path), error=function(e) getwd())
    www_dir <- file.path(app_dir, "www") # Still used for temp storage
    if (!dir.exists(www_dir)) {
       tryCatch(dir.create(www_dir),
                warning = function(w) message(paste("Could not create 'www' directory:", w$message)),
                error = function(e) message(paste("Error creating 'www' directory:", e$message)))
       message("Created www directory (for temp storage) at: ", www_dir)
    } else {
       message("Using www directory (for temp storage) confirmed at: ", www_dir)
    }

    `%||%` <- function(a, b) if (!is.null(a) && a != "") a else b

    results <- reactiveValues(
        scientific_name_display = NULL, common_names = NULL, family = NULL, score = NULL, info_combined = NULL,
        plain_text_common_names = NULL, plain_text_info_parts = list(), identification_message = NULL,
        description_message = NULL, image_path_for_display = NULL
    )

    text_to_clean_sentences <- function(input_text, is_html = FALSE) {
      if (is.null(input_text) || input_text == "") return(character(0))
      plain_text <- input_text
      if (is_html) {
          plain_text <- tryCatch({
              temp_doc <- read_html(paste0("<div>", input_text, "</div>"))
              xml_remove(xml_find_all(temp_doc, ".//script|.//style"))
              html_text(temp_doc, trim = TRUE)
          }, error = function(e) { message(paste("HTML parsing error:", e$message)); "" })
      }
      plain_text <- gsub("\\[\\d+(?:,\\s*\\d+)*\\]", "", plain_text)
      plain_text <- gsub("\\s+", " ", trimws(plain_text))
      if (nchar(plain_text) == 0) return(character(0))
      return(plain_text)
    }

    observeEvent(input$image_upload, {
        if (!is.null(input$image_upload$datapath)) {
        results$image_path_for_display <- input$image_upload$datapath
        results$scientific_name_display <- "Awaiting identification..."
        results$common_names <- ""; results$family <- ""; results$score <- ""; results$info_combined <- ""
        results$identification_message <- "Upload an image and click 'Identify Plant & Get Info'."
        results$description_message <- NULL; results$plain_text_common_names <- NULL; results$plain_text_info_parts <- list()
        session$sendCustomMessage("updateTTSStatus", list(status = "Ready.", enableButton = TRUE))
        }
    })

    output$uploaded_image_display <- renderImage({
        req(results$image_path_for_display, file.exists(results$image_path_for_display))
        list(src = results$image_path_for_display, contentType = input$image_upload$type, alt = "Uploaded Plant Image", height = 300)
    }, deleteFile = FALSE)

    observeEvent(input$identify_btn, {
        req(input$image_upload, input$image_upload$datapath)
        session$sendCustomMessage(type = "playScannerSound", message = list())

        results$scientific_name_display <- "Processing..."
        results$common_names <- ""; results$family <- ""; results$score <- ""; results$info_combined <- ""
        results$identification_message <- "Identifying plant..."
        results$description_message <- NULL; results$plain_text_common_names <- NULL; results$plain_text_info_parts <- list()
        session$sendCustomMessage("updateTTSStatus", list(status = "Identifying...", enableButton = FALSE))

        api_res <- identify_plant_with_api(input$image_upload$datapath, input$organ_type)

        if (!is.null(api_res$error)) {
        results$identification_message <- paste("PlantNet Error:", api_res$error)
        results$scientific_name_display <- "Error during identification"
        session$sendCustomMessage(type = "stopScannerSound", message = list())
        session$sendCustomMessage("updateTTSStatus", list(status = paste("Identification Error:", api_res$error), enableButton = TRUE))
        return()
        }
        results$identification_message <- "PlantNet Identification Successful!"
        results$scientific_name_display <- api_res$full_scientific_name_display
        results$common_names <- api_res$common_names %||% "N/A"
        results$family <- api_res$family %||% "N/A"
        results$score <- if(!is.null(api_res$score)) sprintf("%.2f%%", api_res$score * 100) else "N/A"
        results$plain_text_common_names <- text_to_clean_sentences(api_res$common_names %||% "", is_html = FALSE)

        all_info_parts_html <- c()
        temp_plain_text_info_parts <- c()
        current_status_messages <- c()

        current_status_messages <- c(current_status_messages, "Fetching from POWO...")
        results$description_message <- paste(current_status_messages, collapse="<br>")
        powo_res <- fetch_powo_description(api_res$family, api_res$species_for_powo)
        powo_data_found <- FALSE
        if (!is.null(powo_res$description) && powo_res$description != "") {
        html_chunk <- paste("<b>POWO General Description:</b><br>", powo_res$description)
        all_info_parts_html <- c(all_info_parts_html, html_chunk)
        temp_plain_text_info_parts <- c(temp_plain_text_info_parts, paste("From P O W O:", text_to_clean_sentences(powo_res$description, is_html = FALSE)))
        current_status_messages[length(current_status_messages)] <- "POWO: Description retrieved."
        powo_data_found <- TRUE
        } else {
        current_status_messages[length(current_status_messages)] <- paste("POWO Note:", powo_res$error %||% "No description found.")
        }
        results$description_message <- paste(current_status_messages, collapse="<br>")

        current_status_messages <- c(current_status_messages, "Fetching from PFAF...")
        results$description_message <- paste(current_status_messages, collapse="<br>")
        pfaf_details <- fetch_pfaf_details(api_res$species_for_pfaf_wiki)
        if (!is.null(pfaf_details$error)) {
        current_status_messages[length(current_status_messages)] <- paste("PFAF Error:", pfaf_details$error)
        } else {
        pfaf_temp_parts_html <- c()
        if(!is.null(pfaf_details$hazards) && pfaf_details$hazards != "") {
            html_chunk <- paste("<b>Known Hazards (PFAF):</b>", pfaf_details$hazards)
            pfaf_temp_parts_html <- c(pfaf_temp_parts_html, html_chunk)
            temp_plain_text_info_parts <- c(temp_plain_text_info_parts, paste("Known Hazards from P F A F:", text_to_clean_sentences(pfaf_details$hazards, is_html = FALSE)))
        }
        if(!is.null(pfaf_details$other_uses_sentence) && pfaf_details$other_uses_sentence != "") {
            html_chunk <- paste("<b>Other Uses (PFAF - first sentence):</b>", pfaf_details$other_uses_sentence)
            pfaf_temp_parts_html <- c(pfaf_temp_parts_html, html_chunk)
            temp_plain_text_info_parts <- c(temp_plain_text_info_parts, paste("Other Uses from P F A F:", text_to_clean_sentences(pfaf_details$other_uses_sentence, is_html = FALSE)))
        }
        if(!is.null(pfaf_details$medicinal_uses_sentences) && pfaf_details$medicinal_uses_sentences != "") {
            html_chunk <- paste("<b>Medicinal Uses (PFAF - first 1-2 sentences):</b>", pfaf_details$medicinal_uses_sentences)
            pfaf_temp_parts_html <- c(pfaf_temp_parts_html, html_chunk)
            temp_plain_text_info_parts <- c(temp_plain_text_info_parts, paste("Medicinal Uses from P F A F:", text_to_clean_sentences(pfaf_details$medicinal_uses_sentences, is_html = FALSE)))
        }
        if(length(pfaf_temp_parts_html) > 0){
            all_info_parts_html <- c(all_info_parts_html, pfaf_temp_parts_html)
            current_status_messages[length(current_status_messages)] <- "PFAF: Details retrieved."
        } else {
            current_status_messages[length(current_status_messages)] <- "PFAF: No specific details extracted."
        }
        }
        results$description_message <- paste(current_status_messages, collapse="<br>")

        if (!powo_data_found) {
            current_status_messages <- c(current_status_messages, "Fetching from Wikipedia (as POWO was empty)...")
            results$description_message <- paste(current_status_messages, collapse="<br>")
            wiki_details <- fetch_wikipedia_details(api_res$species_for_pfaf_wiki)
            if (!is.null(wiki_details$error)) {
                current_status_messages[length(current_status_messages)] <- paste("Wikipedia Error:", wiki_details$error)
            } else {
                wiki_temp_parts_html <- c()
                if (!is.null(wiki_details$etymology) && wiki_details$etymology != "") {
                    html_chunk <- paste("<b>Etymology (Wikipedia):</b>", wiki_details$etymology)
                    wiki_temp_parts_html <- c(wiki_temp_parts_html, html_chunk)
                    temp_plain_text_info_parts <- c(temp_plain_text_info_parts, paste("Etymology from Wikipedia:", text_to_clean_sentences(wiki_details$etymology, is_html = FALSE)))
                }
                if (!is.null(wiki_details$intro) && wiki_details$intro != "") {
                    html_chunk <- paste("<b>Introduction (Wikipedia):</b>", wiki_details$intro)
                    wiki_temp_parts_html <- c(wiki_temp_parts_html, html_chunk)
                    temp_plain_text_info_parts <- c(temp_plain_text_info_parts, paste("Introduction from Wikipedia:", text_to_clean_sentences(wiki_details$intro, is_html = FALSE)))
                }
                if(length(wiki_temp_parts_html) > 0){
                    all_info_parts_html <- c(all_info_parts_html, wiki_temp_parts_html)
                    current_status_messages[length(current_status_messages)] <- "Wikipedia: Details retrieved."
                } else {
                    current_status_messages[length(current_status_messages)] <- "Wikipedia: No specific details extracted."
                }
            }
            results$description_message <- paste(current_status_messages, collapse="<br>")
        }

        results$plain_text_info_parts <- temp_plain_text_info_parts

        if(length(all_info_parts_html) > 0) {
            results$info_combined <- HTML(paste(all_info_parts_html, collapse = "<br><br><hr style='border-top: 1px dashed #ccc;'><br>"))
        } else {
            results$info_combined <- HTML("No detailed information could be retrieved for this plant.")
        }

        session$sendCustomMessage(type = "stopScannerSound", message = list())
        if (grepl("Successful!", results$identification_message)) {
            results$identification_message <- "PlantNet Identification Successful! Data fetched."
        } else if (!grepl("Error", results$identification_message)) {
            results$identification_message <- "Processing complete."
        }
        session$sendCustomMessage("updateTTSStatus", list(status = "Ready to read.", enableButton = TRUE))
    })

    observeEvent(input$read_aloud_btn, {
        full_text_to_speak_list <- list()

        if (!is.null(results$scientific_name_display) && results$scientific_name_display != "N/A" && !grepl("Processing|Awaiting|Error", results$scientific_name_display) ) {
            full_text_to_speak_list <- c(full_text_to_speak_list, paste("Scientific Name:", results$scientific_name_display))
        }
        if (!is.null(results$plain_text_common_names) && nzchar(results$plain_text_common_names) && results$plain_text_common_names != "N/A") {
            full_text_to_speak_list <- c(full_text_to_speak_list, paste("Common Names:", results$plain_text_common_names))
        }
        if (length(results$plain_text_info_parts) > 0) {
            full_text_to_speak_list <- c(full_text_to_speak_list, results$plain_text_info_parts)
        }

        full_text_to_speak <- paste(unlist(full_text_to_speak_list), collapse = ". ")
        full_text_to_speak <- trimws(gsub("\\s+", " ", full_text_to_speak))

        if (nzchar(full_text_to_speak)) {
            session$sendCustomMessage("updateTTSStatus", list(status = "Synthesizing audio...", enableButton = FALSE))
            selected_voice <- input$azure_voice_select

            timestamp_nonce <- paste0(as.integer(Sys.time()), "_", sample(1000,1))
            temp_audio_filename_server <- file.path(www_dir, paste0("tts_single_output_", timestamp_nonce, ".wav"))

            old_files <- list.files(www_dir, pattern = "^tts_single_output.*\\.wav$", full.names = TRUE)
            if(length(old_files) > 0) {
               suppressWarnings(file.remove(old_files))
            }

            audio_data_uri <- NULL

            tryCatch({
                py_result <- synthesize_speech_to_file(text_to_speak = full_text_to_speak,
                                                       output_filename = temp_audio_filename_server,
                                                       voice_name = selected_voice)

                if (grepl("Speech synthesized and saved", py_result, ignore.case = TRUE)) {
                    message(paste("Azure TTS success, file saved to:", temp_audio_filename_server))

                    if (file.exists(temp_audio_filename_server)) {
                        message("Reading generated audio file...")
                        audio_data <- tryCatch({
                            readBin(temp_audio_filename_server, "raw", file.info(temp_audio_filename_server)$size)
                        }, error = function(e) {
                            message(paste("Error reading audio file:", e$message))
                            NULL
                        })

                        if (!is.null(audio_data)) {
                            message("Encoding audio data to Base64...")
                            base64_audio <- base64enc::base64encode(audio_data)
                            audio_data_uri <- paste0("data:audio/wav;base64,", base64_audio)
                            message("Data URI created successfully (length ", nchar(audio_data_uri), ").")

                            # Optionally delete the temp file now
                            # message("Removing temporary audio file...")
                            # suppressWarnings(file.remove(temp_audio_filename_server))

                        } else {
                           message("Failed to read audio data after generation.")
                        }
                    } else {
                        message("ERROR: Audio file not found after Python claimed success!")
                    }

                } else {
                    error_message <- paste("Azure TTS failed (Python script reported):", py_result)
                    message(error_message)
                    session$sendCustomMessage("updateTTSStatus", list(status = error_message, enableButton = TRUE))
                }
            }, error = function(e) {
                error_message <- paste("Error calling Python TTS for single block:", e$message)
                message(error_message)
                py_err <- reticulate::py_last_error()
                if(!is.null(py_err)) {
                    message("Python error details from TTS call:")
                    message(py_err$message)
                    error_message <- paste(error_message, "Python detail:", substr(py_err$message, 1, 100))
                }
                session$sendCustomMessage("updateTTSStatus", list(status = error_message, enableButton = TRUE))
            })

            if (!is.null(audio_data_uri)) {
                 session$sendCustomMessage(type = "playSingleAzureAudio", message = list(data_uri = audio_data_uri))
            } else {
                 message("Audio Data URI could not be created. Cannot play audio.")
                 session$sendCustomMessage("updateTTSStatus", list(status = "Error: Could not prepare audio.", enableButton = TRUE))
            }

        } else {
            session$sendCustomMessage("updateTTSStatus", list(status = "No text available to read.", enableButton = TRUE))
        }
    })

    output$identification_status <- renderUI({
        req(results$identification_message)
        message_text <- results$identification_message
        color <- "black"; if (grepl("Error", message_text, ignore.case = TRUE)) color <- "red"
        else if (grepl("Success", message_text, ignore.case = TRUE)) color <- "green"
        else if (grepl("Identifying|Processing", message_text, ignore.case = TRUE)) color <- "blue"
        p(strong(message_text), style = paste0("color:", color, ";"))
    })
    output$plant_scientific_name <- renderText({ results$scientific_name_display %||% "N/A" })
    output$plant_common_names <- renderText({ results$common_names %||% "N/A" })
    output$plant_family <- renderText({ results$family %||% "N/A" })
    output$plantnet_score <- renderText({ results$score %||% "N/A" })

    output$description_status <- renderUI({
        req(results$description_message)
        HTML(paste0("<p style='font-style: italic;'>", results$description_message, "</p>"))
    })

    output$plant_info_combined <- renderUI({
        req(results$info_combined)
        HTML(results$info_combined)
    })

    session$onSessionEnded(function() {
        temp_files <- list.files(path = www_dir, pattern = "^tts_single_output.*\\.wav$", full.names = TRUE)
        if (length(temp_files) > 0) {
            removed_count <- sum(suppressWarnings(file.remove(temp_files)))
            message(paste("Session ended. Cleaned up", removed_count, "temporary TTS file(s) from:", www_dir))
        }
    })
}

print(paste("Current R Working Directory:", getwd()))
print(paste("Expected www path:", file.path(getwd(), "www")))
if (dir.exists(file.path(getwd(), "www"))) {
  print("'www' directory exists in the current R working directory (used for temp storage).")
} else {
  print("'www' directory DOES NOT EXIST in the current R working directory. Will attempt to create for temp storage.")
}
shinyApp(ui = ui, server = server, options = list(host = "0.0.0.0", port = 5050)) # Using port 5050 as an example
