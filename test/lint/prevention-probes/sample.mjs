// ^safe-pwlt ^safe-em3d: replay the retained compiler-authenticated candidate population.
import {readFileSync} from 'node:fs';
const population=JSON.parse(readFileSync(new URL('./adjacent-population.json',import.meta.url),'utf8'));
const duplicates=new Map();
for(const row of population){
  const key=JSON.stringify([row.consumer,row.source,row.fields]);
  row.ordinal=(duplicates.get(key)??0)+1; duplicates.set(key,row.ordinal);
}
population.sort((a,b)=>JSON.stringify([a.consumer,a.source,a.fields]).localeCompare(JSON.stringify([b.consumer,b.source,b.fields])));
let state=20261006;
for(let i=population.length-1;i>0;i--){state=(Math.imul(1664525,state)+1013904223)>>>0;const j=state%(i+1);[population[i],population[j]]=[population[j],population[i]];}
const judgments=readFileSync(new URL('./adjacent-sample.tsv',import.meta.url),'utf8').trim().split('\n').slice(1).map(line=>line.split('\t'));
if(population.length!==279||judgments.length!==40)throw Error('population/sample size changed');
for(let i=0;i<40;i++){
  const r=population[i],j=judgments[i];
  if(JSON.stringify([r.consumer,r.source,...r.fields,String(r.ordinal)])!==JSON.stringify(j.slice(1,7)))throw Error('sample identity changed at '+(i+1));
}
const prone=judgments.filter(j=>j[7]==='swap-prone').length;
if(prone!==11)throw Error('manual classifications changed');
console.log('seed=20261006 population=279 swap-prone=11/40 (27.5%) decision=restricted ordered-endpoint gate');
