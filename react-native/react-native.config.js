module.exports = {
  dependency: {
    platforms: {
      android: {
        sourceDir: './android',
        packageImportPath: 'import tech.bubbl.reactnative.BubblSdkPackage;',
        packageInstance: 'new BubblSdkPackage()',
      },
    },
  },
};
