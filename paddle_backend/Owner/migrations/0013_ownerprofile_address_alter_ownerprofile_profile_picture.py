from django.db import migrations, models


class Migration(migrations.Migration):

    dependencies = [
        ('Owner', '0012_ownerprofile_apple_sub'),
    ]

    operations = [
        migrations.AddField(
            model_name='ownerprofile',
            name='address',
            field=models.CharField(blank=True, default='', max_length=255),
        ),
        migrations.AlterField(
            model_name='ownerprofile',
            name='profile_picture',
            field=models.ImageField(blank=True, null=True, upload_to='owner/profile/'),
        ),
    ]
