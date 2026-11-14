import {build} from 'esbuild';
import {mkdir,copyFile} from 'node:fs/promises';
import {execFileSync} from 'node:child_process';
import path from 'node:path';
await mkdir('dist',{recursive:true});
if (process.platform === 'darwin') {
 execFileSync('../light-recorder-mac/scripts/build-app.sh', [path.resolve('.cache/embedded/Capture/截录暂存.app')], {stdio:'inherit'});
 execFileSync('../trackpad-lock-mac/scripts/build-app.sh', [path.resolve('.cache/embedded/Trackpad/触控板锁.app')], {stdio:'inherit'});
}
await Promise.all([
 build({entryPoints:['src/main.ts'],outfile:'dist/main.cjs',bundle:true,platform:'node',format:'cjs',packages:'external',sourcemap:true}),
 build({entryPoints:['src/preload.ts'],outfile:'dist/preload.cjs',bundle:true,platform:'node',format:'cjs',external:['electron']}),
 build({entryPoints:['src/ui/App.tsx'],outfile:'dist/ui.js',bundle:true,platform:'browser',format:'iife',loader:{'.css':'css'},sourcemap:true}),
 build({entryPoints:['src/render-worker.ts'],outfile:'dist/render-worker.cjs',bundle:true,platform:'node',format:'cjs',packages:'external'})
]);
await copyFile('src/ui/index.html','dist/index.html');
