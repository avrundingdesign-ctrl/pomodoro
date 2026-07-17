import path from "node:path";
import { fileURLToPath } from "node:url";

// Kompiliert liegt diese Datei unter dist/src/ — Projektwurzel ist zwei Ebenen höher.
const here = path.dirname(fileURLToPath(import.meta.url));
export const ROOT = path.resolve(here, "..", "..");
export const VIEWS_DIR = path.join(ROOT, "views");
export const PUBLIC_DIR = path.join(ROOT, "public");
