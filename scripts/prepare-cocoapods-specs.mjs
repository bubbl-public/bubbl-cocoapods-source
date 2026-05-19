import { mkdirSync, readFileSync, writeFileSync } from 'node:fs';
import { join } from 'node:path';
import process from 'node:process';

const root = process.cwd();
const outputDir = join(root, 'build', 'cocoapods');
const sourceUrl = process.env.BUBBL_COCOAPODS_SOURCE_URL;
const sourceTag = process.env.BUBBL_COCOAPODS_SOURCE_TAG;

function read(path) {
  return readFileSync(join(root, path), 'utf8');
}

function write(path, contents) {
  writeFileSync(join(outputDir, path), contents);
}

function rewriteSource(contents) {
  if (!sourceUrl) return contents;

  const replacement = sourceTag
    ? `s.source = { :git => '${sourceUrl}', :tag => '${sourceTag}' }`
    : `s.source = { :git => '${sourceUrl}', :tag => s.version.to_s }`;

  return contents.replace(
    /s\.source\s*=\s*\{\s*:git\s*=>\s*['"][^'"]+['"],\s*:tag\s*=>\s*s\.version\.to_s\s*\}/,
    replacement,
  );
}

mkdirSync(outputDir, { recursive: true });

write('BubblSDK.podspec', rewriteSource(read('ios/BubblSDK.podspec')));
write('Bubbl-Sdk.podspec', rewriteSource(read('ios/Bubbl-Sdk.podspec')));

console.log(`Prepared CocoaPods specs in ${outputDir}`);
if (sourceUrl) {
  console.log(`Using CocoaPods source URL: ${sourceUrl}`);
}
if (sourceTag) {
  console.log(`Using CocoaPods source tag: ${sourceTag}`);
}
