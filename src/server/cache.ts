import { createHash } from 'node:crypto';
import type { Lookup } from '../shared/protocol.ts';
import { promptVersion } from './deepseek.ts';
export function cacheKey(input: Lookup, model: string) {
  const {requestId, ...rest} = input;
  return createHash('sha256').update(JSON.stringify({...rest, selectedText:input.selectedText.trim().normalize('NFC'), model, promptVersion, thinking:'disabled'})).digest('hex');
}
export class Cache {
  private entries = new Map<string,{text:string;returnedModel:string;expires:number}>();
  get(key:string) {
    const entry=this.entries.get(key); if (!entry) return;
    this.entries.delete(key); if (entry.expires<Date.now()) return;
    this.entries.set(key,entry); return entry;
  }
  set(key:string, value:{text:string;returnedModel:string}) {
    if (!value.text.trim()) return;
    this.entries.delete(key); this.entries.set(key,{...value,expires:Date.now()+1800000});
    if (this.entries.size>200) this.entries.delete(this.entries.keys().next().value!);
  }
}
