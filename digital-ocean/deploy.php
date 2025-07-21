<?php
namespace Deployer;

require 'contrib/rsync.php';
require 'recipe/laravel.php';

// Config
set('application', 'laravelapp.senku.stream');
set('keep_releases', 5); // Keep 5 releases
set('http_user', 'unit');
set('http_group', 'unit');

set('rsync_src', __DIR__);

// Hosts
host('laravelapp.senku.stream') // Name of the server
    ->set('hostname', 'laravelapp.senku.stream') // Hostname or IP address
    ->set('remote_user', 'deployer') // SSH user
    ->set('deploy_path', '/var/www/laravelapp.senku.stream'); // Deploy path

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
    // 'artisan:migrate',      // | Run artisan migrate if you need it, if not then just comment it!
    // 'artisan:horizon:terminate',
    // 'artisan:horizon:publish',
    'deploy:publish',
]);

after('deploy:failed', 'deploy:unlock');
