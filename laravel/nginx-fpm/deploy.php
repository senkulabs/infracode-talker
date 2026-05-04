<?php
namespace Deployer;

require 'contrib/rsync.php';
require 'recipe/laravel.php';

// Config
set('application', 'laravel.senku.stream');
set('keep_releases', 5); // Keep 5 releases

/**
 * NOTE:
 * The __DIR__ value means that the source of rsync comes from GitLab CI build
 * (assumes deploy.php is in project root)
 */
set('rsync_src', __DIR__);

// Hosts
host('laravel.senku.stream') // Name of the server
    ->set('hostname', 'laravel.senku.stream')
    ->set('remote_user', 'deployer') // SSH user
    ->set('deploy_path', '/var/www/html'); // Deploy path

// Hooks
task('deploy:secrets', function () {
    file_put_contents(__DIR__.'/.env', getenv('DOTENV'));
    upload('.env', get('deploy_path').'/shared');
});

task('deploy:update_code')->disable();
after('deploy:update_code', 'rsync');
task('deploy', [
    'deploy:prepare',
    'deploy:secrets', // Deploy secrets
    'deploy:vendors',
    'artisan:storage:link', // |
    'artisan:view:cache',   // |
    'artisan:config:cache', // | Laravel specific steps
    'artisan:optimize',     // |
    'artisan:migrate',      // | Run artisan migrate if you need it, if not then just comment it!
    // 'artisan:horizon:terminate',
    // 'artisan:horizon:publish',
    'deploy:publish',
]);

after('deploy:failed', 'deploy:unlock');
