<?php
namespace Deployer;

require 'contrib/rsync.php';
require 'recipe/laravel.php';

// Config
set('application', 'laravel.senku.stream');
set('keep_releases', 5); // Keep 5 releases
set('http_user', 'unit');
set('http_group', 'unit');

/**
 * NOTE:
 * The __DIR__ value means that the source of rsync comes from GitLab CI build
 * (assumes deploy.php is in project root)
 */
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
task('deploy:acme-challenge', function () {
    return run('mkdir -p /var/www/html/.well-known/acme-challenge');
});

task('unit:apply-config', function () {
    run('
        status=$(/usr/bin/curl -X GET --unix-socket /var/run/control.unit.sock -s -o /dev/null -w "%{http_code}" http://localhost/config/applications/laravel)
        if [ "$status" != "200" ]; then
            echo "Applying Unit configuration (Laravel app not found)..."
            curl -X PUT --data-binary @/home/deployer/unit-http.json --unix-socket /var/run/control.unit.sock http://localhost/config/
        else
            echo "Laravel app already exists in Unit, skipping configuration"
        fi
    ');
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
    'deploy:acme-challenge',
    'artisan:storage:link', // |
    'artisan:view:cache',   // |
    'artisan:config:cache', // | Laravel specific steps
    'artisan:optimize',     // |
    'artisan:migrate',      // | Run artisan migrate if you need it, if not then just comment it!
    // 'artisan:horizon:terminate',
    // 'artisan:horizon:publish',
    'deploy:publish',
    'unit:apply-config',
    'unit:reload',
]);

after('deploy:failed', 'deploy:unlock');