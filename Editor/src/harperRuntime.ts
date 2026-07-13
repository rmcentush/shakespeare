import {
  createBinaryModuleFromUrl,
  Dialect,
  Linter,
  LocalLinter,
  WorkerLinter,
} from 'harper.js';

declare global {
  interface Window {
    harperRuntime?: {
      createWorkerLinter(wasmURL: string, dialect: number): Linter;
      createLocalLinter(wasmURL: string, dialect: number): Linter;
    };
  }
}

function normalizedDialect(value: number): Dialect {
  return value >= Dialect.American && value <= Dialect.Indian
    ? value as Dialect
    : Dialect.American;
}

window.harperRuntime = {
  createWorkerLinter(wasmURL: string, dialect: number): Linter {
    return new WorkerLinter({
      binary: createBinaryModuleFromUrl(wasmURL, 'slim'),
      dialect: normalizedDialect(dialect),
    });
  },
  createLocalLinter(wasmURL: string, dialect: number): Linter {
    return new LocalLinter({
      binary: createBinaryModuleFromUrl(wasmURL, 'slim'),
      dialect: normalizedDialect(dialect),
    });
  },
};
