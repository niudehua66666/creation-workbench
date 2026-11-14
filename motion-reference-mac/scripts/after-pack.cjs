const {execFileSync}=require('node:child_process');
const path=require('node:path');
const fs=require('node:fs');
module.exports=async function(context){
 const app=path.join(context.appOutDir,context.packager.appInfo.productFilename+'.app');
 // This app compiles new projects at runtime, so declaration files are runtime assets.
 // electron-builder normally drops them even from production dependencies.
 const copyDeclarations=(source,destination)=>{
  if(fs.existsSync(path.join(source,'package.json'))&&!fs.existsSync(path.join(destination,'package.json')))return;
  for(const entry of fs.readdirSync(source,{withFileTypes:true})){
   if(entry.name.startsWith('.'))continue;const s=path.join(source,entry.name),d=path.join(destination,entry.name);
   if(entry.isDirectory())copyDeclarations(s,d);
   else if(/\.d\.(ts|mts|cts)$/.test(entry.name)){fs.mkdirSync(path.dirname(d),{recursive:true});fs.copyFileSync(s,d);}
  }
 };
 copyDeclarations(path.join(context.packager.projectDir,'node_modules'),path.join(app,'Contents/Resources/app/node_modules'));
 execFileSync('/usr/bin/codesign',['--force','--deep','--sign','-',app]);
};
