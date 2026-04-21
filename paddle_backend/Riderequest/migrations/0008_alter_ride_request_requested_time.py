from django.db import migrations, models


class Migration(migrations.Migration):

    dependencies = [
        ('Riderequest', '0007_ride_request_riderequest_rider_i_02f33a_idx_and_more'),
    ]

    operations = [
        migrations.AlterField(
            model_name='ride_request',
            name='requested_time',
            field=models.DateTimeField(blank=True, default=None, null=True),
        ),
    ]
