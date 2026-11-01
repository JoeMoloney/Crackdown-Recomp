#include "game_files.h"

#include <algorithm>
#include <cstdio>
#include <filesystem>
#include <iostream>
#include <string>

namespace {

void PrintUsage(const char* program) {
  std::cerr << "Usage: " << program << " <disc.iso> <output-folder>\n"
            << "Extracts and validates the supported Crackdown Xbox 360 disc.\n";
}

bool ShowProgress(const crackdown::InstallProgress& progress) {
  const unsigned percent = progress.total_bytes == 0
                               ? 0
                               : static_cast<unsigned>(std::min<uint64_t>(
                                     100, progress.done_bytes * 100 / progress.total_bytes));
  std::fprintf(stderr, "\r%-28s %3u%%", progress.phase.c_str(), percent);
  std::fflush(stderr);
  return true;
}

}  // namespace

int main(int argc, char** argv) {
  if (argc == 2 && (std::string(argv[1]) == "--help" || std::string(argv[1]) == "-h")) {
    PrintUsage(argv[0]);
    return 0;
  }
  if (argc != 3) {
    PrintUsage(argv[0]);
    return 2;
  }

  const std::filesystem::path image = argv[1];
  const std::filesystem::path destination = argv[2];
  crackdown::InstallHooks hooks;
  hooks.progress = ShowProgress;

  std::cerr << "Extracting and validating game files...\n";
  const crackdown::InstallResult result = crackdown::InstallGame(image, destination, hooks);
  std::cerr << '\n';
  if (!result.ok()) {
    const crackdown::InstallMessage message = crackdown::DescribeInstall(result.status);
    std::cerr << message.title << ": " << message.text;
    if (!result.detail.empty()) {
      std::cerr << " (" << result.detail << ')';
    }
    std::cerr << '\n';
    return 1;
  }

  const crackdown::GameFiles check = crackdown::CheckGameFiles(destination);
  if (check.state != crackdown::GameFiles::kReady) {
    std::cerr << "Extraction completed, but validation failed: " << check.detail << '\n';
    return 1;
  }

  std::cout << "Game extracted and validated at " << std::filesystem::absolute(destination).string() << '\n';
  std::cout << "The source ISO was left untouched.\n";
  return 0;
}
