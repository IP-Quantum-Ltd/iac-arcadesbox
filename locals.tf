locals {
  # This reads the content of the bundled worker script.
  # Make sure you run "npm run build" before running terraform.
  worker_script_content = file("dist/game_gatekeeper.js")
}
