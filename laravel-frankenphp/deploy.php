<?php

namespace Deployer;

require 'contrib/rsync.php';
require 'recipe/laravel.php';

// Config
set('http_user', 'frankenphp');
set('keep_releases', 5); // Keep 5 releases

/**
 * NOTE:
 * The __DIR__ value means that the source of rsync comes from GitLab CI build
 * (assumes deploy.php is in project root)
 */
set('rsync_src', __DIR__);

// Hosts
host('sandbox.web.app')
    ->set('hostname', getenv('DEPLOY_HOST_SANDBOX'))
    ->set('remote_user', 'deployer')
    ->set('deploy_path', '/var/www/{{alias}}')
    ->set('dotenv_var', 'DOTENV_SANDBOX');

host('web.app')
    ->set('hostname', getenv('DEPLOY_HOST_PROD'))
    ->set('remote_user', 'deployer')
    ->set('deploy_path', '/var/www/{{alias}}')
    ->set('dotenv_var', 'DOTENV_PROD');

// Hooks
task('deploy:secrets', function () {
    $file = getenv(get('dotenv_var'));
    upload($file, get('deploy_path').'/shared/.env');
});

task('deploy:update_code')->disable();
after('deploy:update_code', 'rsync');
task('deploy', [
    'deploy:prepare',
    'deploy:secrets',
    'deploy:vendors',
    'deploy:writable',
    'artisan:storage:link',
    'artisan:migrate',
    'artisan:optimize',
    'deploy:publish',
    'artisan:queue:restart',
]);

after('deploy:failed', 'deploy:unlock');
