import {test} from 'node:test';
import assert from 'node:assert/strict';
import {splitAnswer} from '../src/client/answer.ts';
test('streamed meaning stays intact before a complete paragraph separator arrives',()=>{
 assert.deepEqual(splitAnswer('值得坚持到底的立场。\r'),{meaning:'值得坚持到底的立场。',explanation:'',separated:false});
 assert.deepEqual(splitAnswer('值得坚持到底的立场。\r\n\r\n这里'),{meaning:'值得坚持到底的立场。',explanation:'这里',separated:true});
});
test('paragraph split preserves explanation and falls back without deleting or guessing text',()=>{
 assert.deepEqual(splitAnswer('私信额度\n \nDM 指私信。\n\n未说明具体数量。'),{meaning:'私信额度',explanation:'DM 指私信。\n\n未说明具体数量。',separated:true});
 assert.equal(splitAnswer('这句话的意思是：值得坚持。这里指一种立场。').meaning,'这句话的意思是：值得坚持。这里指一种立场。');
});
