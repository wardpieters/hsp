import { execFile } from 'node:child_process';
import { mkdtemp, mkdir, readFile, writeFile, rm } from 'node:fs/promises';
import { tmpdir } from 'node:os';
import { join, resolve } from 'node:path';
import { promisify } from 'node:util';
const exec = promisify(execFile);

// Render via the actual provider resource, never by copying the template logic.
export async function renderedFiles(directory, filter, runName) {
  const { stdout } = await exec('terraform', [`-chdir=${resolve(directory)}`, 'test', `-filter=${filter}`, '-json', '-verbose'], { maxBuffer: 25 * 1024 * 1024 });
  for (const line of stdout.split('\n')) {
    if (!line.startsWith('{')) continue;
    const event = JSON.parse(line);
    if (runName && event['@testrun'] !== runName) continue;
    const resources = event.test_state?.root_module?.resources ?? event.test_plan?.resource_changes?.map(r => ({ ...r, values: r.change.after }));
    if (resources?.some(r => r.type === 'system_file' && r.values.content?.includes('# hsp-network-helper'))) {
      return { ...Object.fromEntries(resources.filter(r => r.type === 'system_file').map(r => [r.name, r.values.content])), teardown: resources.find(r => r.type === 'terraform_data' && /^(he_)?teardown$/.test(r.name))?.values.input };
    }
  }
  throw Error('No rendered network helper in Terraform test plan/state');
}

export async function networkFixture(t, script, files = {}) {
  const dir = await mkdtemp(join(tmpdir(), 'hsp-network-'));
  t.after(() => rm(dir, { recursive: true, force: true }));
  await mkdir(join(dir, 'bin')); await mkdir(join(dir, 'runtime'));
  await mkdir(join(dir, 'config'));
  for (const [name, content] of Object.entries(files)) await writeFile(join(dir, 'config', name), content);
  const state = join(dir, 'state.json');
  await writeFile(state, JSON.stringify({ links: {}, routes: [], tables: {}, log: [], flows: [] }));
  const fake = `#!${process.execPath}
import fs from 'node:fs';
import path from 'node:path';
import { spawnSync } from 'node:child_process';
const file=process.env.HSP_FAKE_STATE, s=JSON.parse(fs.readFileSync(file)), tool=path.basename(process.argv[1]), a=process.argv.slice(2), cmd=a.join(' ');
const done=(out='',code=0)=>{fs.writeFileSync(file,JSON.stringify(s));if(out)process.stdout.write(out+'\\n');process.exit(code);};
s.log.push(tool+' '+cmd);
if(s.fail && s.fail.tool===tool && cmd.includes(s.fail.match)){delete s.fail;done('injected command failure',2);}
if(tool==='systemctl') {
 if(a[0]!=='stop')done('unexpected systemctl command',99);
 if(s.serviceActive===false)done();
 s.serviceActive=false;fs.writeFileSync(file,JSON.stringify(s));
 const result=spawnSync('/bin/sh',[process.env.HSP_FAKE_HELPER,'stop'],{env:process.env,encoding:'utf8'});
 process.stdout.write(result.stdout??'');process.stderr.write(result.stderr??'');process.exit(result.status??1);
}
if(tool==='sysctl')done();
if(tool==='ip6tables-save') done(s.raw??'');
if(tool==='conntrack') {
 const filters={'--orig-src':'origSrc','--orig-dst':'origDst','--reply-dst':'replyDst','--dport':'port','-p':'proto','--zone':'zone'};
 if(a.includes('-D'))s.flows=s.flows.filter(flow=>!Object.entries(filters).every(([flag,key])=>!a.includes(flag)||String(flow[key])===a[a.indexOf(flag)+1]));
 done();
}
if(tool==='nft') {
 if(cmd==='list tables')done(Object.keys(s.tables).map(n=>'table ip6 '+n).join('\\n'));
 if(a[0]==='list'&&a[1]==='table')done(s.tables[a[3]]??'',s.tables[a[3]]?0:1);
 if(a.includes('-f')) {const f=a[a.indexOf('-f')+1], content=fs.readFileSync(f,'utf8'); if(!a.includes('-c')) {for(const m of content.matchAll(/delete table ip6 (\\w+)/g))delete s.tables[m[1]];for(const m of content.matchAll(/(?:^|\\n)table ip6 (\\w+) \\{/g))s.tables[m[1]]=content;}done();}
 if(a[0]==='delete'&&a[1]==='table'){delete s.tables[a[3]];done();}
 done('unexpected nft command '+cmd,99);
}
if(tool==='ip') {
 const dev=a.includes('dev')?a[a.indexOf('dev')+1]:null;
 if(a.includes('link')&&a.includes('show')){const l=s.links[dev];done(l?dev+' '+l.type+' alias '+l.alias:'',l?0:1);}
 if(a[0]==='tunnel'&&(a[1]==='add'||a[1]==='change')){const n=a[2];if(a[1]==='add'&&s.links[n])done('exists',2);s.links[n]={...s.links[n],type:'sit',tunnel:a.slice(2).join(' '),addresses:s.links[n]?.addresses??[]};done();}
 if(a[0]==='link'&&a[1]==='add'){if(s.links[a[2]])done('exists',2);s.links[a[2]]={type:'dummy',addresses:[]};done();}
 if(a[0]==='link'&&a[1]==='set'){if(!s.links[dev])done('absent',2);if(a.includes('alias'))s.links[dev].alias=a[a.indexOf('alias')+1];if(a.includes('mtu'))s.links[dev].mtu=Number(a[a.indexOf('mtu')+1]);if(a.includes('up'))s.links[dev].up=true;done();}
 if(a[0]==='link'&&a[1]==='delete'){delete s.links[dev];s.routes=s.routes.filter(r=>!r.includes('dev '+dev));done();}
 if(a[0]==='-6'&&(a[1]==='address'||a[1]==='addr')){if(!s.links[dev])done('absent',2);if(a[2]==='flush')s.links[dev].addresses=[];else if(a[2]==='replace')s.links[dev].addresses=[a[3]];else done('unknown address action',99);done();}
 if(a[0]==='-6'&&a[1]==='route'){
  if(a[2]==='show'){let r=s.routes;if(a.includes('default'))r=r.filter(x=>x.startsWith('default '));if(a.includes('metric'))r=r.filter(x=>x.includes('metric '+a[a.indexOf('metric')+1]));done(r.join('\\n'));}
  const route=a.slice(3).join(' ');if(a[2]==='replace'){s.routes=s.routes.filter(r=>!(r.split('metric ')[1]===route.split('metric ')[1] && (r.split(' ').slice(0,r.startsWith('blackhole')?2:1).join(' ')===route.split(' ').slice(0,route.startsWith('blackhole')?2:1).join(' '))));s.routes.push(route);done();}
  if(a[2]==='del'){s.routes=s.routes.filter(r=>r!==route);done();}
 }
 done('unexpected ip command '+cmd,99);
}
done('unexpected tool',99);
`;
  for (const tool of ['ip', 'nft', 'sysctl', 'conntrack', 'ip6tables-save', 'systemctl']) await writeFile(join(dir, 'bin', tool), fake, { mode: 0o755 });
  const scriptPath = join(dir, 'helper.sh'); await writeFile(scriptPath, script, { mode: 0o700 });
  return {
    dir, scriptPath,
    read: async () => JSON.parse(await readFile(state, 'utf8')),
    seed: async changes => { const s = JSON.parse(await readFile(state)); await writeFile(state, JSON.stringify({ ...s, ...changes })); },
    configure: async files => { for (const [name, content] of Object.entries(files)) await writeFile(join(dir, 'config', name), content); },
    teardown: command => exec('/bin/sh', ['-c', command.replaceAll('/usr/bin/systemctl', 'systemctl').replace(/\/(?:etc\/hsp-ipv6-ingress\/ingress|usr\/local\/lib\/hsp-he-ipv6\/routing)\.sh/g, scriptPath)], { env: { ...process.env, PATH: `${join(dir, 'bin')}:/usr/bin:/bin:/usr/sbin:/sbin`, RUNTIME_DIRECTORY: join(dir, 'runtime'), CONFIGURATION_DIRECTORY: join(dir, 'config'), HSP_FAKE_STATE: state, HSP_FAKE_HELPER: scriptPath } }),
    run: action => exec('/bin/sh', [scriptPath, action], { env: { ...process.env, PATH: `${join(dir, 'bin')}:/usr/bin:/bin:/usr/sbin:/sbin`, RUNTIME_DIRECTORY: join(dir, 'runtime'), CONFIGURATION_DIRECTORY: join(dir, 'config'), HSP_FAKE_STATE: state } }),
  };
}
