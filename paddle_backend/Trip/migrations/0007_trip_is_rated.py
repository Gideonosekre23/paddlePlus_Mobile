from django.db import migrations, models


class Migration(migrations.Migration):

    dependencies = [
        ('Trip', '0006_trip_payment_intent_id'),
    ]

    operations = [
        migrations.AddField(
            model_name='trip',
            name='is_rated',
            field=models.BooleanField(default=False),
        ),
    ]
