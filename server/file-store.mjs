import { readFile, mkdir, rename, writeFile } from "node:fs/promises";
import { dirname } from "node:path";

export class MemoryStore {
  records = new Map();
  key(pk, sk) {
    return `${pk}|${sk}`;
  }
  async get(pk, sk) {
    return this.records.get(this.key(pk, sk)) || null;
  }
  async put(pk, sk, value) {
    this.records.set(this.key(pk, sk), value);
  }
  async putOnce(pk, sk, value) {
    const key = this.key(pk, sk);
    if (!this.records.has(key)) this.records.set(key, value);
  }
  async query(pk) {
    return [...this.records]
      .filter(([key]) => key.startsWith(`${pk}|`))
      .map(([, value]) => value);
  }
}

export class FileStore extends MemoryStore {
  pending = Promise.resolve();
  constructor(path) {
    super();
    this.path = path;
  }
  async load() {
    try {
      this.records = new Map(JSON.parse(await readFile(this.path, "utf8")));
    } catch (error) {
      if (error.code !== "ENOENT") throw error;
    }
    return this;
  }
  async persist() {
    this.pending = this.pending
      .catch(() => {})
      .then(async () => {
        await mkdir(dirname(this.path), { recursive: true });
        await writeFile(`${this.path}.tmp`, JSON.stringify([...this.records]));
        await rename(`${this.path}.tmp`, this.path);
      });
    return this.pending;
  }
  async put(...args) {
    await super.put(...args);
    await this.persist();
  }
  async putOnce(...args) {
    await super.putOnce(...args);
    await this.persist();
  }
}
