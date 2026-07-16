type Target = "wasm-gc" | "wasm" | "js" | "native" | "llvm";

type patchAdd = {
  name: string;
  content: string;
};

type patchDrop = {
  file: string;
  index: number;
};

type patches = {
  drops: patchDrop[];
  patches: patchAdd[];
};

type checkParams = {
  mbtFiles: [string, string][];
  miFiles: [string, Uint8Array][];
  indirectImportMiFiles: [string, Uint8Array][];
  stdMiFiles: [string, Uint8Array][];
  target: Target;
  pkg: string;
  pkgSources: string[];
  isMain: boolean;
  patches?: patches;
  errorFormat: "human" | "json";
  warnAsError?: boolean;
};

type checkResult = {
  mi: Uint8Array;
  diagnostics: string[];
};

type buildPackageParams = {
  mbtFiles: [string, string][];
  miFiles: [string, Uint8Array][];
  indirectImportMiFiles: [string, Uint8Array][];
  stdMiFiles: [string, Uint8Array][];
  target: Target;
  pkg: string;
  pkgSources: string[];
  isMain: boolean;
  errorFormat: "human" | "json";
  enableValueTracing: boolean;
  noOpt: boolean;
};

type buildPackageResult = {
  core?: Uint8Array;
  mi?: Uint8Array;
  diagnostics: string[];
};

type linkCoreParams = {
  coreFiles: Uint8Array[];
  main: string;
  pkgSources: string[];
  target: Target;
  exportedFunctions: string[];
  outputFormat: "wasm" | "wat";
  testMode: boolean;
  debug: boolean;
  noOpt: boolean;
  sourceMap: boolean;
  sourceMapUrl?: string;
  sources: { [key: string]: string };
  stopOnMain: boolean;
};

type linkCoreResult = {
  result: Uint8Array;
  sourceMap?: string;
};

type genTestInfoParams = {
  mbtFiles: [string, string][];
};

declare function check(params: checkParams): checkResult;
declare function buildPackage(params: buildPackageParams): buildPackageResult;
declare function linkCore(params: linkCoreParams): linkCoreResult;
declare function genTestInfo(params: genTestInfoParams): string;

export { check, buildPackage, linkCore, genTestInfo };
export type {
  checkParams,
  buildPackageParams,
  linkCoreParams,
  genTestInfoParams,
  patches,
};
