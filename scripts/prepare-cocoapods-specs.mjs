import { mkdirSync, readFileSync, writeFileSync } from 'node:fs';
import { join } from 'node:path';
import process from 'node:process';

const root = process.cwd();
const outputDir = join(root, 'build', 'cocoapods');
const sourceUrl = process.env.BUBBL_COCOAPODS_SOURCE_URL;

function read(path) {
  return readFileSync(join(root, path), 'utf8');
}

function write(path, contents) {
  writeFileSync(join(outputDir, path), contents);
}

function rewriteSource(contents) {
  if (!sourceUrl) return contents;

  return contents.replace(
    /s\.source\s*=\s*\{\s*:git\s*=>\s*['"][^'"]+['"],\s*:tag\s*=>\s*s\.version\.to_s\s*\}/,
    `s.source = { :git => '${sourceUrl}', :tag => s.version.to_s }`,
  );
}

mkdirSync(outputDir, { recursive: true });

write('BubblSDK.podspec', rewriteSource(read('ios/BubblSDK.podspec')));
write('Bubbl-Sdk.podspec', rewriteSource(read('ios/Bubbl-Sdk.podspec')));

console.log(`Prepared CocoaPods specs in ${outputDir}`);
if (sourceUrl) {
  console.log(`Using CocoaPods source URL: ${sourceUrl}`);
}
