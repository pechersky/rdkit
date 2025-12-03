// Tautomer canonicalization profiler for perf benchmarking.
// Mirrors the Python rdkit_generate_canonical_tautomer workflow.
//
// Usage:
//   ./bin/tautomer_canonicalize_profile --input molecules.sdf --repeats 5
//
// This executable reads molecules from an SDF file, configures a
// TautomerEnumerator with production-like settings, and runs canonicalization
// for the specified number of repeats to gather stable perf measurements.

#include <chrono>
#include <cstring>
#include <iostream>
#include <memory>
#include <string>
#include <vector>

#include <GraphMol/FileParsers/MolSupplier.h>
#include <GraphMol/MolStandardize/Tautomer.h>
#include <GraphMol/ROMol.h>
#include <GraphMol/SmilesParse/SmilesWrite.h>

using namespace RDKit;

namespace {

struct Options {
  std::string inputFile = "registry_sample.sdf";
  unsigned int repeats = 5;
};

void printUsage(const char *progName) {
  std::cerr << "Usage: " << progName << " [options]\n"
            << "Options:\n"
            << "  --input <file>    Input SDF file (default: registry_sample.sdf)\n"
            << "  --repeats <N>     Number of canonicalization repeats (default: 5)\n"
            << "  --help            Show this help message\n";
}

bool parseArgs(int argc, char *argv[], Options &opts) {
  for (int i = 1; i < argc; ++i) {
    if (std::strcmp(argv[i], "--input") == 0 || std::strcmp(argv[i], "-i") == 0) {
      if (i + 1 >= argc) {
        std::cerr << "Error: --input requires a value\n";
        return false;
      }
      opts.inputFile = argv[++i];
    } else if (std::strcmp(argv[i], "--repeats") == 0 ||
               std::strcmp(argv[i], "-r") == 0) {
      if (i + 1 >= argc) {
        std::cerr << "Error: --repeats requires a value\n";
        return false;
      }
      opts.repeats = static_cast<unsigned int>(std::stoul(argv[++i]));
    } else if (std::strcmp(argv[i], "--help") == 0 ||
               std::strcmp(argv[i], "-h") == 0) {
      printUsage(argv[0]);
      std::exit(0);
    } else {
      std::cerr << "Unknown option: " << argv[i] << "\n";
      printUsage(argv[0]);
      return false;
    }
  }
  return true;
}

}  // namespace

int main(int argc, char *argv[]) {
  Options opts;
  if (!parseArgs(argc, argv, opts)) {
    return 1;
  }

  // Load molecules from SDF
  std::vector<std::unique_ptr<ROMol>> molecules;
  {
    SDMolSupplier supplier(opts.inputFile, true /* sanitize */,
                           true /* removeHs */, true /* strictParsing */);
    while (!supplier.atEnd()) {
      std::unique_ptr<ROMol> mol(supplier.next());
      if (mol) {
        molecules.push_back(std::move(mol));
      }
    }
  }

  if (molecules.empty()) {
    std::cerr << "Error: No molecules loaded from " << opts.inputFile << "\n";
    return 1;
  }

  std::cout << "Loaded " << molecules.size() << " molecules from "
            << opts.inputFile << "\n";

  // Configure TautomerEnumerator to match production settings:
  //   - MaxTautomers = 20
  //   - MaxTransforms = 20
  //   - RemoveBondStereo = false (preserve E/Z)
  //   - RemoveSp3Stereo = false (preserve chiral centers)
  MolStandardize::TautomerEnumerator enumerator;
  enumerator.setMaxTautomers(20);
  enumerator.setMaxTransforms(20);
  enumerator.setRemoveBondStereo(false);
  enumerator.setRemoveSp3Stereo(false);

  // Warm-up pass (excluded from timing)
  for (const auto &mol : molecules) {
    std::unique_ptr<ROMol> canonical(enumerator.canonicalize(*mol));
    (void)canonical;  // suppress unused warning
  }

  // Timed canonicalization runs
  const auto totalCanonicalizations = molecules.size() * opts.repeats;
  const auto startTime = std::chrono::high_resolution_clock::now();

  for (unsigned int rep = 0; rep < opts.repeats; ++rep) {
    for (const auto &mol : molecules) {
      std::unique_ptr<ROMol> canonical(enumerator.canonicalize(*mol));
      (void)canonical;
    }
  }

  const auto endTime = std::chrono::high_resolution_clock::now();
  const auto elapsedMs =
      std::chrono::duration_cast<std::chrono::milliseconds>(endTime - startTime)
          .count();
  const double avgMs =
      static_cast<double>(elapsedMs) / static_cast<double>(totalCanonicalizations);

  std::cout << "Completed " << totalCanonicalizations << " canonicalizations ("
            << molecules.size() << " molecules x " << opts.repeats
            << " repeats)\n";
  std::cout << "Total time: " << elapsedMs << " ms\n";
  std::cout << "Average per canonicalization: " << avgMs << " ms\n";

  return 0;
}
