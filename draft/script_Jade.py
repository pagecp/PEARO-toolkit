from datetime import datetime, timedelta

#maybe also get precip before erasing MF data?
#example_grib = xr.open_dataset('/archive2/globc/arpaliangeas/PEARO_2022/test/mb001/2022-06-01_T21:00:00_grid.arome-forecast.eurw1s40+0018:00.grib')


def get_date_two_days_before(date_str, slash=False):
    date = datetime.strptime(date_str, "%Y-%m-%d")
    date_before = date - timedelta(days=2)
    year_before = str(date_before.year)
    month_before = str(date_before.month).zfill(2)
    day_before = str(date_before.day).zfill(2)
    if slash:
        return f"{year_before}/{month_before}/{day_before}"
    return f"{year_before}-{month_before}-{day_before}"

def update_tas_max(prov_tas_max, temp_instant):
    new_tas_max = np.maximum(prov_tas_max, temp_instant)
    return new_tas_max


for member in range(1,26):
    str_member = "0" + str(member) if len(str(member))==1 else str(member)
    tasmax_list_member = []
    for date in list_dates:
        prov_tas_max = np.zeros((717, 1121)) #or other dim. latitude: 717, longitude: 1121
        for hour in range(12,24):
            date_str = date[0:10]
            date_PE_archive2 = get_date_two_days_before(date_str, slash=False)
            str1_archive2 = f"/archive2/globc/arpaliangeas/PEARO_2022/full_PEARO_2022/mb0{str_member}/" 
            str2_archive2 = f"_T21:00:00_grid.arome-forecast.eurw1s40+00{hour}:00.grib"
            str_to_get_archive2 = str1_archive2 + date_PE_archive2 + str2_archive2


            grib_data = xr.open_dataset(str_to_get_archive2, engine="cfgrib", filter_by_keys={'stepType': 'max', 'typeOfLevel': 'surface'})
            temp_instant = grib_data['t'].values
            tas_max = update_tas_max(prov_tas_max, temp_instant)

        #need to recover the date
        xr_tas_max = xr.DataArray(
            data=tas_max,
            dims=grib_data.dims,
            coords=grib_data.dims,
            attrs=grib_data.dims,
        )
        
        
        tasmax_list_member.append(xr_tas_max)
    
    xr.concat(tasmax_list_member, dim="time")
    #tasmax_list_member.to_netcdf(f'/archive2/globc/arpaliangeas/PEARO_2022/clean_PEARO_2022/extreme_tasmax_PEARO_2022/mb0{str_member}')