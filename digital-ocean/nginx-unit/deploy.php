<?php
namespace Deployer;

require 'contrib/rsync.php';
require 'recipe/laravel.php';

// Config
set('application', 'laravel.senku.stream');
set('keep_releases', 5); // Keep 5 releases
set('http_user', 'unit');
set('http_group', 'unit');

set('rsync_src', __DIR__);

// Hosts
host('laravel.senku.stream') // Name of the server
    ->set('hostname', 'laravel.senku.stream') // Hostname or IP address
    ->set('remote_user', 'deployer') // SSH user
    ->set('deploy_path', '/var/www/html'); // Deploy path

// Hooks
task('deploy:secrets', function () {
    file_put_contents(__DIR__.'/.env', getenv('DOTENV'));
    upload('.env', get('deploy_path').'/shared');
});

// Create a .well-known/acme-challenge for let's encrypt SSL certificate verification
task('deployer:acme-challenge', function () {
    return run('mkdir -p /var/www/html/.well-known/acme-challenge');
});

task('unit:reload', function () {
    return run('/usr/bin/curl -X GET --unix-socket /var/run/control.unit.sock http://localhost/control/applications/laravel/restart');
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
    'deployer:acme-challenge',
    'unit:reload',
]);

after('deploy:failed', 'deploy:unlock');