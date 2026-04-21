from django.db import migrations, models


class Migration(migrations.Migration):

    dependencies = [
        ('Owner', '0006_alter_ownerprofile_profile_picture'),
    ]

    operations = [
        migrations.AlterField(
            model_name='ownerprofile',
            name='profile_picture',
            field=models.ImageField(blank=True, null=True, upload_to='profile_pics/'),
        ),
    ]
