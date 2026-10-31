#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/../.."
mkdir -p work/mobile-completion
xcrun swiftc -parse-as-library -o work/mobile-completion/mobile-regression \
  apple/KintampoMarket/Models/{Product,MoreModels}.swift \
  apple/KintampoMarket/Services/{AppConfig,AdminAPI,APIClient,CartStore,SessionVault,StorefrontCatalog,SupabaseService}.swift \
  apple/Tests/MobileRegression.swift
work/mobile-completion/mobile-regression
