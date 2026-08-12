declare module "expo-modules-core" {
  export function requireNativeModule<T>(name: string): T;
}

declare module "node:fs/promises" {
  export function mkdir(path: string, options: { recursive: boolean }): Promise<unknown>;
  export function writeFile(path: string, data: string, encoding: string): Promise<void>;
}

declare module "node:path" {
  export function dirname(path: string): string;
}
