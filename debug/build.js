const esbuild = require('esbuild');

const isWatch = process.argv.includes('--watch');

const buildOptions = {
    entryPoints: ['src/extension.ts'],
    bundle: true,
    outfile: 'dist/extension.js', // Output to a 'dist' folder
    platform: 'node',
    target: 'node18', // Target VS Code's typical Node.js version
    format: 'cjs',    // Output CommonJS format
    external: ['vscode'], // Mark 'vscode' as external, it's provided by the runtime
    sourcemap: true,     // Generate source maps for debugging
    logLevel: 'info',
};

if (isWatch) {
    esbuild.context(buildOptions).then(ctx => {
        console.log('Watching for changes...');
        ctx.watch();
    }).catch(err => {
        console.error('Watch build failed:', err);
        process.exit(1);
    });
} else {
    esbuild.build(buildOptions).catch(err => {
        console.error('Build failed:', err);
        process.exit(1);
    });
} 